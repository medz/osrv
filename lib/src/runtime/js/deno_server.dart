import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../core/config.dart';
import '../../types/runtime.dart';
import '../server_transport.dart';
import 'web_converters.dart';

extension type DenoServeOptions._(JSObject _) implements JSObject {
  external factory DenoServeOptions({
    int? port,
    String? hostname,
    bool? reusePort,
    JSFunction? onListen,
  });
}

extension type DenoAddr._(JSObject _) implements JSObject {
  external String get hostname;
  external int get port;
}

extension type DenoServeInfo._(JSObject _) implements JSObject {
  external DenoAddr get remoteAddr;
}

extension type DenoNativeServer._(JSObject _) implements JSObject {
  external DenoAddr get addr;
  external JSPromise<JSAny?> shutdown();
}

@JS('Deno')
extension type Deno._(JSAny _) {
  external static DenoNativeServer serve(
    DenoServeOptions options,
    JSFunction handler,
  );
}

final class DenoServerTransport implements ServerTransport {
  DenoServerTransport({
    required ServerConfig config,
    required DispatchRequest dispatch,
  }) : _config = config,
       _dispatch = dispatch;

  final ServerConfig _config;
  final DispatchRequest _dispatch;

  DenoNativeServer? _runtime;
  Future<void>? _readyFuture;

  @override
  Runtime get runtime => const Runtime(name: 'deno', kind: RuntimeKind.deno);

  @override
  String get hostname => _runtime?.addr.hostname ?? _config.hostname;

  @override
  int get port => _runtime?.addr.port ?? _config.port;

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
  Future<void> serve() async {
    if (_runtime != null) {
      return;
    }

    final readyCompleter = Completer<void>();
    void onListen() {
      if (!readyCompleter.isCompleted) {
        readyCompleter.complete();
      }
    }

    final options = DenoServeOptions(
      hostname: _config.hostname,
      port: _config.port,
      reusePort: _config.reusePort,
      onListen: onListen.toJS,
    );

    _runtime = Deno.serve(options, _handleRequest.toJS);
    _readyFuture = readyCompleter.future;
  }

  @override
  Future<void> ready() => _readyFuture ?? Future<void>.value();

  @override
  Future<void> close({required bool force}) async {
    final runtime = _runtime;
    if (runtime == null) {
      return;
    }
    await runtime.shutdown().toDart;
  }

  JSPromise<web.Response> _handleRequest(
    web.Request request,
    DenoServeInfo info,
  ) {
    return _dispatchRequest(request, info).toJS;
  }

  Future<web.Response> _dispatchRequest(
    web.Request request,
    DenoServeInfo info,
  ) async {
    final remote = info.remoteAddr;
    final serverRequest = webRequestToServerRequest(
      request,
      ip: remote.hostname,
      context: <String, Object?>{'runtime': runtime.name},
    );

    final response = await _dispatch(serverRequest);
    return htResponseToWebResponse(response);
  }
}
