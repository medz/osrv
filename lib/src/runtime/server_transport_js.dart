import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:ht/ht.dart' show Headers, Request, Response;

import '../request.dart';
import '../types.dart';
import 'server_transport.dart';

@JS('globalThis')
external JSObject get _globalThis;

const String _mainKey = '__osrv_main__';
const String _mainReadyResolveKey = '__osrv_main_ready_resolve__';
const String _bridgeModeKey = '__osrv_bridge__';
const String _bridgeModeValue = 'json-v1';
const String _runtimeCapabilitiesKey = '__osrv_runtime_capabilities__';

ServerTransport createServerTransport(ServerTransportHost host) {
  return _JsBridgeServerTransport(host);
}

final class _JsBridgeServerTransport implements ServerTransport {
  _JsBridgeServerTransport(this._host);

  final ServerTransportHost _host;
  late final String _runtimeName = _detectRuntimeName();
  JSFunction? _bridgeFunction;
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

    final bridge = (JSAny? payloadJson, JSFunction resolve, JSFunction reject) {
      _dispatchPayload(payloadJson).then(
        (responseJson) {
          resolve.callAsFunction(resolve, responseJson.toJS);
        },
        onError: (Object error, StackTrace stackTrace) {
          _host.logError('JS bridge dispatch failed', error, stackTrace);
          resolve.callAsFunction(resolve, _encodeFatalBridgeError(error).toJS);
        },
      );
      reject; // Keep static arity stable for JS callers.
    }.toJS;

    bridge.setProperty(_bridgeModeKey.toJS, _bridgeModeValue.toJS);
    _globalThis.setProperty(_mainKey.toJS, bridge);
    final readyResolve = _globalThis.getProperty(_mainReadyResolveKey.toJS);
    if (readyResolve.isA<JSFunction>()) {
      (readyResolve as JSFunction).callAsFunction(readyResolve, bridge);
    }

    _bridgeFunction = bridge;
    _registered = true;

    if (!_host.silent) {
      _host.logInfo(
        'JS bridge registered on globalThis.__osrv_main__ ($_runtimeName)',
      );
    }
  }

  @override
  Future<void> close({required bool force}) async {
    if (!_registered) {
      return;
    }

    final current = _globalThis.getProperty(_mainKey.toJS);
    if (_bridgeFunction != null && current == _bridgeFunction) {
      _globalThis.setProperty(_mainKey.toJS, null);
    }
    _bridgeFunction = null;
    _registered = false;
  }

  Future<String> _dispatchPayload(JSAny? payloadJson) async {
    if (payloadJson == null || !payloadJson.isA<JSString>()) {
      throw StateError('Bridge payload must be a JSON string.');
    }

    final payloadString = payloadJson as JSString;
    final decoded = jsonDecode(payloadString.toDart);
    if (decoded is! Map) {
      throw StateError('Bridge payload JSON must be an object.');
    }

    final payload = Map<String, Object?>.from(decoded);
    final requestPayload = _mapFrom(payload['request']);
    final runtimePayload = _mapFrom(payload['runtime']);
    final contextPayload = _mapFrom(payload['context']);

    List<Future<Object?>>? waitUntilTasks;
    void waitUntil(Future<Object?> task) {
      (waitUntilTasks ??= <Future<Object?>>[]).add(task);
      _host.trackBackgroundTask(task);
    }

    final request = _decodeRequest(requestPayload);
    final runtime = _decodeRuntime(runtimePayload, waitUntil);
    final ip = _stringOrNull(runtimePayload['ip']);

    request.runtime = runtime;
    request.context = contextPayload;
    request.ip = ip;
    request.waitUntil = waitUntil;

    final response = await _host.dispatch(request);
    if (waitUntilTasks case final tasks?) {
      await Future.wait(tasks, eagerError: false);
    }

    return _encodeResponse(response);
  }

  ServerRequest _decodeRequest(Map<String, Object?> payload) {
    final urlRaw = payload['url'];
    if (urlRaw is! String || urlRaw.isEmpty) {
      throw StateError('Bridge request.url must be a non-empty string.');
    }
    final method = _stringOr(payload['method'], 'GET').toUpperCase();

    final headers = Headers();
    final headerList = payload['headers'];
    if (headerList is List) {
      for (final item in headerList) {
        if (item is List && item.length >= 2) {
          headers.append(item[0].toString(), item[1].toString());
        }
      }
    }

    Object? body;
    final bodyBase64 = payload['bodyBase64'];
    if (bodyBase64 is String && bodyBase64.isNotEmpty) {
      body = Uint8List.fromList(base64Decode(bodyBase64));
    }

    return ServerRequest(
      Request(Uri.parse(urlRaw), method: method, headers: headers, body: body),
    );
  }

  RequestRuntimeContext _decodeRuntime(
    Map<String, Object?> payload,
    WaitUntil waitUntil,
  ) {
    final protocol = _stringOr(
      payload['protocol'],
      _host.resolvedProtocol == ServerProtocol.https ? 'https' : 'http',
    );
    final httpVersion = _stringOr(payload['httpVersion'], '1.1');
    final runtime = _stringOr(payload['runtime'], _runtimeName);
    final tls = _boolOr(payload['tls'], protocol == 'https');
    final env = _mapFrom(payload['env']);

    final provider = _stringOr(payload['provider'], runtime);
    final rawPayload = Map<String, Object?>.from(payload);
    final raw = switch (provider) {
      'node' => RuntimeRawContext(node: rawPayload),
      'bun' => RuntimeRawContext(bun: rawPayload),
      'deno' => RuntimeRawContext(deno: rawPayload),
      'cloudflare' => RuntimeRawContext(cloudflare: rawPayload),
      'vercel' => RuntimeRawContext(vercel: rawPayload),
      'netlify' => RuntimeRawContext(netlify: rawPayload),
      _ => const RuntimeRawContext(),
    };

    return RequestRuntimeContext(
      name: runtime,
      protocol: protocol,
      httpVersion: httpVersion,
      tls: tls,
      localAddress: _stringOrNull(payload['localAddress']),
      remoteAddress: _stringOrNull(payload['remoteAddress']),
      waitUntil: waitUntil,
      env: env,
      raw: raw,
    );
  }

  Future<String> _encodeResponse(Response response) async {
    final headers = <List<String>>[];
    for (final entry in response.headers) {
      headers.add(<String>[entry.key, entry.value]);
    }

    String? bodyBase64;
    if (response.body != null) {
      final bytes = await response.bytes();
      if (bytes.isNotEmpty) {
        bodyBase64 = base64Encode(bytes);
      }
    }

    return jsonEncode(<String, Object?>{
      'status': response.status,
      'headers': headers,
      'bodyBase64': bodyBase64,
    });
  }

  String _encodeFatalBridgeError(Object error) {
    final body = jsonEncode(<String, Object>{
      'ok': false,
      'error': 'Bridge dispatch failed',
      'details': error.toString(),
    });
    return jsonEncode(<String, Object?>{
      'status': 500,
      'headers': const <List<String>>[
        <String>['content-type', 'application/json; charset=utf-8'],
      ],
      'bodyBase64': base64Encode(utf8.encode(body)),
    });
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

  Map<String, Object?> _mapFrom(Object? value) {
    if (value is! Map) {
      return <String, Object?>{};
    }
    return value.map(
      (key, dynamic mapValue) => MapEntry(key.toString(), mapValue as Object?),
    );
  }

  String _stringOr(Object? value, String fallback) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return fallback;
  }

  String? _stringOrNull(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  bool _boolOr(Object? value, bool fallback) {
    if (value is bool) {
      return value;
    }
    return fallback;
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
