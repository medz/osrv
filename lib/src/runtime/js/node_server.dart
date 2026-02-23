import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:ht/ht.dart';

import '../../core/config.dart';
import '../../request.dart';
import '../../types/runtime.dart';
import '../server_transport.dart';

extension type IncomingHttpHeaders._(JSObject _) implements JSObject {
  external String? get host;
}

@JS('Object')
extension type JSObjectStatic._(JSAny _) {
  external static JSArray<JSArray<JSAny?>> entries(JSObject value);
}

@JS('Array')
extension type JSArrayStatic._(JSAny _) {
  external static bool isArray(JSAny? value);
}

extension type NodeSocket._(JSObject _) implements JSObject {
  external String? get remoteAddress;
  external String? get remoteFamily;
  external int? get remotePort;
  external String? get localAddress;
}

extension type NodeIncomingMessage._(JSObject _) implements JSObject {
  external IncomingHttpHeaders get headers;
  external String? get url;
  external String? get method;
  external NodeSocket get socket;

  external void on(JSString event, JSFunction listener);
}

extension type NodeServerResponse._(JSObject _) implements JSObject {
  external void writeHead(int statusCode, JSArray<JSArray<JSString>> headers);
  external void write(JSAny chunk);
  external void end();
}

extension type NodeListenOptions._(JSObject _) implements JSObject {
  external factory NodeListenOptions({
    String? host,
    int? port,
    bool? exclusive,
  });
}

extension type NodeAddressInfo._(JSObject _) implements JSObject {
  external String get address;
  external int get port;
}

extension type NodeNativeServer._(JSObject _) implements JSObject {
  external NodeNativeServer listen(
    NodeListenOptions options,
    JSFunction callback,
  );
  external void close([JSFunction? callback]);
  external void closeAllConnections();
  external JSAny? address();
}

extension type NodeHttp._(JSObject _) implements JSObject {
  external NodeNativeServer createServer(JSFunction listener);
}

final class NodeServerTransport implements ServerTransport {
  NodeServerTransport({
    required ServerConfig config,
    required DispatchRequest dispatch,
  }) : _config = config,
       _dispatch = dispatch;

  final ServerConfig _config;
  final DispatchRequest _dispatch;

  NodeNativeServer? _runtime;
  Future<void>? _serveFuture;
  Future<void>? _readyFuture;

  @override
  Runtime get runtime => const Runtime(name: 'node', kind: RuntimeKind.node);

  @override
  String get hostname {
    final runtime = _runtime;
    if (runtime == null) {
      return _config.hostname;
    }

    final address = runtime.address();
    if (address != null && address.isA<JSString>()) {
      return (address as JSString).toDart;
    }

    if (address != null && address.isA<JSObject>()) {
      return (address as NodeAddressInfo).address;
    }

    return _config.hostname;
  }

  @override
  int get port {
    final runtime = _runtime;
    if (runtime == null) {
      return _config.port;
    }

    final address = runtime.address();
    if (address != null && address.isA<JSObject>()) {
      return (address as NodeAddressInfo).port;
    }

    return _config.port;
  }

  @override
  Uri get url => Uri(
    scheme: _config.secure ? 'https' : 'http',
    host: hostname,
    port: port,
  );

  @override
  String get addr {
    final host = hostname.contains(':') ? '[$hostname]' : hostname;
    return '$host:$port';
  }

  @override
  Future<void> serve() {
    return _serveFuture ??= _startServer();
  }

  @override
  Future<void> ready() => _readyFuture ?? _serveFuture ?? Future<void>.value();

  @override
  Future<void> close({required bool force}) async {
    final runtime = _runtime;
    if (runtime == null) {
      return;
    }

    if (force) {
      runtime.closeAllConnections();
    }

    final completer = Completer<void>();

    void onClosed() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    runtime.close(onClosed.toJS);
    await completer.future;
  }

  Future<void> _startServer() async {
    final module = await importModule('node:http'.toJS).toDart;
    final http = module as NodeHttp;

    final readyCompleter = Completer<void>();
    _readyFuture = readyCompleter.future;

    void onReady() {
      if (!readyCompleter.isCompleted) {
        readyCompleter.complete();
      }
    }

    _runtime = http.createServer(_onRequest.toJS);
    _runtime!.listen(
      NodeListenOptions(
        host: _config.hostname,
        port: _config.port,
        exclusive: !_config.reusePort,
      ),
      onReady.toJS,
    );

    await _readyFuture;
  }

  void _onRequest(NodeIncomingMessage request, NodeServerResponse response) {
    unawaited(_dispatchNodeRequest(request, response));
  }

  Future<void> _dispatchNodeRequest(
    NodeIncomingMessage request,
    NodeServerResponse response,
  ) async {
    try {
      final method = (request.method ?? 'GET').toUpperCase();
      final headers = _decodeHeaders(request.headers);
      final url = _buildUrl(request, headers);

      final body = _methodAllowsBody(method)
          ? _requestBodyStream(request)
          : null;
      final fetchRequest = Request(
        url,
        method: method,
        headers: headers,
        body: body,
      );

      final ip = request.socket.remoteAddress ?? '';
      final serverRequest = createServerRequest(
        fetchRequest,
        ip: ip,
        context: <String, Object?>{'runtime': runtime.name},
      );

      final outgoing = await _dispatch(serverRequest);

      final responseHeaders = <JSArray<JSString>>[];
      for (final entry in outgoing.headers) {
        responseHeaders.add([entry.key.toJS, entry.value.toJS].toJS);
      }

      response.writeHead(outgoing.status, responseHeaders.toJS);

      final bodyStream = outgoing.body;
      if (bodyStream case final stream?) {
        await for (final chunk in stream) {
          response.write(chunk.toJS);
        }
      }
      response.end();
    } catch (_) {
      response.writeHead(
        500,
        [
          ['content-type'.toJS, 'text/plain; charset=utf-8'.toJS].toJS,
        ].toJS,
      );
      response.write('Internal Server Error'.toJS);
      response.end();
    }
  }

  Headers _decodeHeaders(IncomingHttpHeaders source) {
    final headers = Headers();
    for (final entry in JSObjectStatic.entries(source).toDart) {
      final parts = entry.toDart;
      if (parts.length < 2) {
        continue;
      }

      final nameAny = parts[0];
      final valueAny = parts[1];
      if (nameAny == null || !nameAny.isA<JSString>()) {
        continue;
      }

      final name = (nameAny as JSString).toDart;
      if (valueAny != null && JSArrayStatic.isArray(valueAny)) {
        for (final item in (valueAny as JSArray<JSAny?>).toDart) {
          if (item != null && item.isA<JSString>()) {
            headers.append(name, (item as JSString).toDart);
          }
        }
        continue;
      }

      if (valueAny != null && valueAny.isA<JSString>()) {
        headers.append(name, (valueAny as JSString).toDart);
      }
    }

    return headers;
  }

  Uri _buildUrl(NodeIncomingMessage request, Headers headers) {
    final methodHost = headers.get('host') ?? request.socket.localAddress;
    final host = methodHost == null || methodHost.isEmpty
        ? _config.hostname
        : methodHost;
    final rawPath = request.url ?? '/';

    if (rawPath.startsWith('http://') || rawPath.startsWith('https://')) {
      return Uri.parse(rawPath);
    }

    final normalizedPath = rawPath.startsWith('/') ? rawPath : '/$rawPath';
    final scheme = _config.secure ? 'https' : 'http';
    return Uri.parse('$scheme://$host$normalizedPath');
  }

  Stream<Uint8List> _requestBodyStream(NodeIncomingMessage request) {
    final controller = StreamController<Uint8List>();

    void onData(JSAny? chunk) {
      final bytes = _toBytes(chunk);
      if (bytes.isNotEmpty) {
        controller.add(bytes);
      }
    }

    void onEnd() {
      if (!controller.isClosed) {
        controller.close();
      }
    }

    void onError(JSAny? error) {
      if (!controller.isClosed) {
        controller.addError(StateError('Node request stream failed: $error'));
        controller.close();
      }
    }

    request.on('data'.toJS, onData.toJS);
    request.on('end'.toJS, onEnd.toJS);
    request.on('error'.toJS, onError.toJS);

    return controller.stream;
  }

  Uint8List _toBytes(JSAny? chunk) {
    if (chunk == null) {
      return Uint8List(0);
    }

    if (chunk.isA<JSUint8Array>()) {
      return (chunk as JSUint8Array).toDart;
    }

    if (chunk.isA<JSArrayBuffer>()) {
      return Uint8List.view((chunk as JSArrayBuffer).toDart);
    }

    if (chunk.isA<JSString>()) {
      return Uint8List.fromList(utf8.encode((chunk as JSString).toDart));
    }

    return Uint8List(0);
  }

  static bool _methodAllowsBody(String method) {
    return method != 'GET' && method != 'HEAD' && method != 'TRACE';
  }
}
