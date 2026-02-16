import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import 'package:ht/ht.dart' show Headers, Request, Response;
import 'package:web/web.dart' as web;

import '../types.dart';
import 'server_request_impl.dart';
import 'server_transport.dart';

@JS('globalThis')
external JSObject get _globalThis;

const String _mainKey = '__osrv_main__';
const String _mainReadyResolveKey = '__osrv_main_ready_resolve__';
const String _runtimeCapabilitiesKey = '__osrv_runtime_capabilities__';

const String _upgradeResponseMarker = '__osrv_upgrade_response__';
const String _wsUpgradeHeader = 'x-osrv-upgrade';
const String _wsUpgradeValue = 'websocket';

ServerTransport createServerTransport(ServerTransportHost host) {
  return _JsDirectServerTransport(host);
}

final class _JsDirectServerTransport implements ServerTransport {
  _JsDirectServerTransport(this._host);

  final ServerTransportHost _host;
  late final String _runtimeName = _detectRuntimeName();
  JSFunction? _mainFunction;
  bool _registered = false;

  @override
  String get runtimeName => _runtimeName;

  @override
  ServerCapabilities get capabilities {
    final edge =
        _runtimeName == 'cloudflare' ||
        _runtimeName == 'vercel' ||
        _runtimeName == 'netlify';
    final http2 = _readRuntimeCapabilityBool('http2') ?? false;
    final websocket = _readRuntimeCapabilityBool('websocket') ?? false;
    return ServerCapabilities(
      http1: true,
      https: true,
      http2: http2,
      websocket: websocket,
      requestStreaming: false,
      responseStreaming: false,
      waitUntil: true,
      edge: edge,
      tls: true,
      edgeProviders: edge ? <String>{_runtimeName} : const <String>{},
    );
  }

  @override
  String? get url {
    final protocol = _host.resolvedProtocol == ServerProtocol.https
        ? 'https'
        : 'http';
    return '$protocol://${_host.resolvedHostname}:${_host.resolvedPort}';
  }

  @override
  Future<void> serve() async {
    if (_registered) {
      return;
    }

    final main = ((JSAny? requestAny, JSAny? contextAny) {
      return _dispatchRequest(requestAny, contextAny).toJS;
    }).toJS;

    _globalThis.setProperty(_mainKey.toJS, main);
    final readyResolve = _globalThis.getProperty(_mainReadyResolveKey.toJS);
    if (readyResolve.isA<JSFunction>()) {
      (readyResolve as JSFunction).callAsFunction(readyResolve, main);
    }

    _mainFunction = main;
    _registered = true;

    if (!_host.silent) {
      _host.logInfo(
        'JS direct handler registered on globalThis.__osrv_main__ ($_runtimeName)',
      );
    }
  }

  @override
  Future<void> close({required bool force}) async {
    if (!_registered) {
      return;
    }

    final current = _globalThis.getProperty(_mainKey.toJS);
    if (_mainFunction != null && current == _mainFunction) {
      _globalThis.setProperty(_mainKey.toJS, null);
    }
    _mainFunction = null;
    _registered = false;
  }

  Future<JSAny?> _dispatchRequest(JSAny? requestAny, JSAny? contextAny) async {
    if (requestAny == null || !requestAny.isA<web.Request>()) {
      throw StateError('Direct payload must provide a standard Web Request.');
    }

    final request = requestAny as web.Request;
    final method = request.method.toUpperCase();
    final headers = _decodeHeaders(request.headers);

    Object? body;
    if (_methodAllowsBody(method)) {
      final cloned = request.clone();
      final buffer = await cloned.arrayBuffer().toDart;
      final bytes = Uint8List.view(buffer.toDart);
      if (bytes.isNotEmpty) {
        body = bytes;
      }
    }

    final fetchRequest = Request(
      Uri.parse(request.url),
      method: method,
      headers: headers,
      body: body,
    );

    List<Future<Object?>>? waitUntilTasks;
    final runtimeWaitUntil = _decodeRuntimeWaitUntil(contextAny);
    void waitUntil(Future<Object?> task) {
      (waitUntilTasks ??= <Future<Object?>>[]).add(task);
      _host.trackBackgroundTask(task);
      runtimeWaitUntil?.call(task);
    }

    final runtime = _decodeRuntime(contextAny, waitUntil);
    final ip = _stringOrNull(_property(contextAny, 'ip'));
    final contextBag = _mapFrom(_property(contextAny, 'context'));

    final serverRequest = createServerRequest(
      fetchRequest,
      runtimeResolver: () => runtime,
      ipResolver: () => ip,
      waitUntil: waitUntil,
      context: contextBag,
    );

    final response = await Future<Response>.value(
      _host.dispatch(serverRequest),
    );
    if (waitUntilTasks case final tasks?) {
      await Future.wait(tasks, eagerError: false);
    }

    return _encodeResponse(response);
  }

  Headers _decodeHeaders(web.Headers source) {
    final headers = Headers();
    final callback = ((JSAny? value, JSAny? key, JSAny? ignored) {
      final name = _stringOrNull(key);
      final headerValue = _stringOrNull(value);
      if (name == null || headerValue == null) {
        return;
      }
      headers.append(name, headerValue);
    }).toJS;
    js_util.callMethod<void>(source, 'forEach', <Object?>[callback]);
    return headers;
  }

  RuntimeRawContext _decodeRawContext(JSAny? contextAny, String provider) {
    final payload = contextAny;
    return switch (provider) {
      'node' => RuntimeRawContext(node: payload),
      'bun' => RuntimeRawContext(bun: payload),
      'deno' => RuntimeRawContext(deno: payload),
      'cloudflare' => RuntimeRawContext(cloudflare: payload),
      'vercel' => RuntimeRawContext(vercel: payload),
      'netlify' => RuntimeRawContext(netlify: payload),
      _ => const RuntimeRawContext(),
    };
  }

  RequestRuntimeContext _decodeRuntime(JSAny? contextAny, WaitUntil waitUntil) {
    final protocol = _stringOr(
      _property(contextAny, 'protocol'),
      _host.resolvedProtocol == ServerProtocol.https ? 'https' : 'http',
    );
    final httpVersion = _stringOr(_property(contextAny, 'httpVersion'), '1.1');
    final runtime = _stringOr(_property(contextAny, 'runtime'), _runtimeName);
    final provider = _stringOr(_property(contextAny, 'provider'), runtime);
    final tls = _boolOr(_property(contextAny, 'tls'), protocol == 'https');
    final env = _mapFrom(_property(contextAny, 'env'));

    return RequestRuntimeContext(
      name: runtime,
      protocol: protocol,
      httpVersion: httpVersion,
      tls: tls,
      localAddress: _stringOrNull(_property(contextAny, 'localAddress')),
      remoteAddress: _stringOrNull(_property(contextAny, 'remoteAddress')),
      waitUntil: waitUntil,
      env: env,
      raw: _decodeRawContext(contextAny, provider),
    );
  }

  WaitUntil? _decodeRuntimeWaitUntil(JSAny? contextAny) {
    final waitUntilAny = _property(contextAny, 'waitUntil');
    if (waitUntilAny is! JSAny || !waitUntilAny.isA<JSFunction>()) {
      return null;
    }
    final waitUntilFn = waitUntilAny as JSFunction;
    final thisArg = contextAny != null && contextAny.isA<JSObject>()
        ? contextAny as JSObject
        : waitUntilFn;

    return (Future<Object?> task) {
      final promise = task.then((_) {}).toJS;
      waitUntilFn.callAsFunction(thisArg, promise);
    };
  }

  Future<JSAny?> _encodeResponse(Response response) async {
    final headers = web.Headers();
    for (final entry in response.headers) {
      headers.append(entry.key, entry.value);
    }

    final upgrade = headers.get(_wsUpgradeHeader);
    final isUpgradeHint =
        upgrade != null && upgrade.toLowerCase() == _wsUpgradeValue;
    if (isUpgradeHint) {
      headers.delete(_wsUpgradeHeader);
    }

    if (response.status == 101 || isUpgradeHint) {
      final marker = js_util.newObject();
      js_util.setProperty(marker, _upgradeResponseMarker, true);
      js_util.setProperty(marker, 'status', 101);
      js_util.setProperty(marker, 'headers', headers);
      return marker as JSAny;
    }

    JSAny? body;
    if (response.body != null) {
      final bytes = await response.bytes();
      if (bytes.isNotEmpty) {
        body = bytes.toJS;
      }
    }

    final init = web.ResponseInit(
      status: response.status,
      statusText: response.statusText,
      headers: headers,
    );
    final next = web.Response(body, init);
    return next as JSAny;
  }

  String _detectRuntimeName() {
    if (_globalThis.hasProperty('Bun'.toJS).toDart) {
      return 'bun';
    }
    if (_globalThis.hasProperty('Deno'.toJS).toDart) {
      return 'deno';
    }
    if (_globalThis.hasProperty('__STATIC_CONTENT'.toJS).toDart) {
      return 'cloudflare';
    }
    if (_globalThis.hasProperty('EdgeRuntime'.toJS).toDart) {
      return 'vercel';
    }
    if (_globalThis.hasProperty('Netlify'.toJS).toDart) {
      return 'netlify';
    }
    if (_globalThis.hasProperty('process'.toJS).toDart) {
      return 'node';
    }
    return 'js';
  }

  Object? _property(JSAny? source, String name) {
    if (source == null || !source.isA<JSObject>()) {
      return null;
    }
    final object = source as JSObject;
    if (!js_util.hasProperty(object, name)) {
      return null;
    }
    return js_util.getProperty<Object?>(object, name);
  }

  String _stringOr(Object? value, String fallback) {
    final normalized = _stringOrNull(value);
    if (normalized != null && normalized.isNotEmpty) {
      return normalized;
    }
    return fallback;
  }

  String? _stringOrNull(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    if (value is JSAny && value.isA<JSString>()) {
      final dart = (value as JSString).toDart;
      if (dart.isNotEmpty) {
        return dart;
      }
      return null;
    }
    return null;
  }

  bool _boolOr(Object? value, bool fallback) {
    final normalized = _boolOrNull(value);
    if (normalized == null) {
      return fallback;
    }
    return normalized;
  }

  bool? _boolOrNull(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is JSAny && value.isA<JSBoolean>()) {
      return (value as JSBoolean).toDart;
    }
    return null;
  }

  Map<String, Object?> _mapFrom(Object? value) {
    final converted = value is JSAny ? _tryDartify(value) : value;
    if (converted is! Map) {
      return <String, Object?>{};
    }
    return converted.map(
      (key, dynamic mapValue) => MapEntry(key.toString(), mapValue as Object?),
    );
  }

  Object? _tryDartify(JSAny value) {
    try {
      return js_util.dartify(value);
    } catch (_) {
      return null;
    }
  }

  bool _methodAllowsBody(String method) {
    if (method == 'GET' || method == 'HEAD' || method == 'TRACE') {
      return false;
    }

    final normalized = method.toUpperCase();
    return normalized != 'GET' && normalized != 'HEAD' && normalized != 'TRACE';
  }

  bool? _readRuntimeCapabilityBool(String name) {
    final raw = _globalThis.getProperty(_runtimeCapabilitiesKey.toJS);
    if (!raw.isA<JSObject>()) {
      return null;
    }

    final value = (raw as JSObject).getProperty(name.toJS);
    if (value.isA<JSBoolean>()) {
      return (value as JSBoolean).toDart;
    }

    return null;
  }
}
