import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../core/config.dart';
import '../../types/runtime.dart';
import '../server_transport.dart';
import 'web_converters.dart';

extension type BunSocketAddress._(JSObject _) implements JSObject {
  external String get address;
  external int get port;
  external String get family;
}

extension type BunNativeServer._(JSObject _) implements JSObject {
  external String get hostname;
  external int get port;
  external web.URL get url;
  external void stop([bool closeActiveConnections]);
  external BunSocketAddress requestIP(web.Request request);
}

extension type BunServeOptions._(JSObject _) implements JSObject {
  external factory BunServeOptions({
    String? hostname,
    int? port,
    bool? reusePort,
    JSFunction fetch,
  });
}

@JS('Bun')
extension type Bun._(JSAny _) {
  external static BunNativeServer serve(BunServeOptions options);
}

final class BunServerTransport implements ServerTransport {
  BunServerTransport({
    required ServerConfig config,
    required DispatchRequest dispatch,
  }) : _config = config,
       _dispatch = dispatch;

  final ServerConfig _config;
  final DispatchRequest _dispatch;

  BunNativeServer? _runtime;

  @override
  Runtime get runtime => const Runtime(name: 'bun', kind: RuntimeKind.bun);

  @override
  String get hostname => _runtime?.hostname ?? _config.hostname;

  @override
  int get port => _runtime?.port ?? _config.port;

  @override
  Uri get url => _runtime == null
      ? _config.defaultUrl()
      : Uri.parse(_runtime!.url.toString());

  @override
  String get addr {
    final host = hostname.contains(':') ? '[$hostname]' : hostname;
    return '$host:$port';
  }

  @override
  Future<void> serve() async {
    if (_runtime != null) {
      return;
    }

    _runtime = Bun.serve(
      BunServeOptions(
        hostname: _config.hostname,
        port: _config.port,
        reusePort: _config.reusePort,
        fetch: _handleRequest.toJS,
      ),
    );
  }

  @override
  Future<void> ready() => Future<void>.value();

  @override
  Future<void> close({required bool force}) async {
    _runtime?.stop(force);
  }

  JSPromise<web.Response> _handleRequest(
    web.Request request,
    BunNativeServer server,
  ) {
    return _dispatchRequest(request, server).toJS;
  }

  Future<web.Response> _dispatchRequest(
    web.Request request,
    BunNativeServer server,
  ) async {
    String ip = '';
    try {
      final address = server.requestIP(request);
      ip = address.address;
    } catch (_) {
      ip = '';
    }

    final serverRequest = webRequestToServerRequest(
      request,
      ip: ip,
      context: <String, Object?>{'runtime': runtime.name},
    );

    final response = await _dispatch(serverRequest);
    return htResponseToWebResponse(response);
  }
}
