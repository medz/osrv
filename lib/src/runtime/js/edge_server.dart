import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../core/config.dart';
import '../../request.dart';
import '../../types/runtime.dart';
import '../../websocket/internal.dart';
import '../../websocket/websocket_js.dart';
import '../server_transport.dart';
import 'global.dart';
import 'web_converters.dart';

extension type _WaitUntilContext._(JSObject _) implements JSObject {
  external JSAny? get waitUntil;
}

final class EdgeServerTransport implements ServerTransport {
  EdgeServerTransport({
    required JsPlatform platform,
    required ServerConfig config,
    required DispatchRequest dispatch,
    required TrackBackgroundTask trackBackgroundTask,
  }) : _platform = platform,
       _config = config,
       _dispatch = dispatch,
       _trackBackgroundTask = trackBackgroundTask;

  final JsPlatform _platform;
  final ServerConfig _config;
  final DispatchRequest _dispatch;
  final TrackBackgroundTask _trackBackgroundTask;

  JSFunction? _registeredFetch;
  JSFunction? _previousFetch;

  @override
  Runtime get runtime => runtimeForJsPlatform(_platform);

  @override
  String get hostname => _config.hostname;

  @override
  int get port => _config.port;

  @override
  Uri get url => _config.defaultUrl();

  @override
  String get addr {
    final host = hostname.contains(':') ? '[$hostname]' : hostname;
    return '$host:$port';
  }

  @override
  Future<void> serve() async {
    if (_registeredFetch != null) {
      return;
    }

    _previousFetch = globalThis.osrvFetch;
    final handler = _handleFetch.toJS;
    globalThis.osrvFetch = handler;
    _registeredFetch = handler;
  }

  @override
  Future<void> ready() => Future<void>.value();

  @override
  Future<void> close({required bool force}) async {
    final registered = _registeredFetch;
    if (registered == null) {
      return;
    }

    if (globalThis.osrvFetch == registered) {
      globalThis.osrvFetch = _previousFetch;
    }

    _registeredFetch = null;
    _previousFetch = null;
  }

  JSPromise<web.Response> _handleFetch(
    web.Request request,
    JSAny? arg1,
    JSAny? arg2,
  ) {
    return _dispatchEdgeRequest(request, arg1, arg2).toJS;
  }

  Future<web.Response> _dispatchEdgeRequest(
    web.Request request,
    JSAny? arg1,
    JSAny? arg2,
  ) async {
    final contextObject = _resolveContextObject(arg1, arg2);
    final waitUntil = _resolveWaitUntil(contextObject);

    final ip =
        request.headers.get('cf-connecting-ip') ??
        request.headers.get('x-forwarded-for')?.split(',').first.trim() ??
        '';

    final serverRequest = webRequestToServerRequest(
      request,
      ip: ip,
      waitUntil: waitUntil,
      context: <String, Object?>{
        'runtime': runtime.name,
        jsRuntimeKey: runtime.name,
        jsRawRequestKey: request,
        jsRawContextKey: contextObject,
      },
    );

    final response = await _dispatch(serverRequest);
    if (isWebSocketUpgradeResponse(response)) {
      final pending = takePendingWebSocketUpgrade(serverRequest);
      if (pending == null) {
        return htResponseToWebResponse(
          webSocketUpgradeErrorResponse(
            'Missing websocket upgrade state in edge transport.',
          ),
        );
      }

      final runtimeResponse = await pending.accept();
      if (runtimeResponse == null) {
        throw StateError('Edge websocket upgrade did not return a Response.');
      }
      return runtimeResponse as web.Response;
    }

    return htResponseToWebResponse(response);
  }

  JSObject? _resolveContextObject(JSAny? arg1, JSAny? arg2) {
    final third = _asObject(arg2);
    if (_hasWaitUntil(third)) {
      return third;
    }

    final second = _asObject(arg1);
    if (_hasWaitUntil(second)) {
      return second;
    }

    return third ?? second;
  }

  WaitUntil _resolveWaitUntil(JSObject? context) {
    final waitUntilFunction = _resolveWaitUntilFunction(context);
    if (waitUntilFunction == null || context == null) {
      return _defaultWaitUntil;
    }

    return <T>(FutureOr<T> Function() run) {
      final task = Future<T>.sync(run);
      _trackBackgroundTask(
        task.then<Object?>(
          (_) => null,
          onError: (Object _, StackTrace _) => null,
        ),
      );

      final promise = task
          .then<JSAny?>((_) => null, onError: (Object _, StackTrace _) => null)
          .toJS;
      waitUntilFunction.callAsFunction(context, promise);
    };
  }

  JSFunction? _resolveWaitUntilFunction(JSObject? context) {
    if (context == null) {
      return null;
    }

    final any = _WaitUntilContext._(context).waitUntil;
    if (any != null && any.isA<JSFunction>()) {
      return any as JSFunction;
    }
    return null;
  }

  bool _hasWaitUntil(JSObject? context) {
    return _resolveWaitUntilFunction(context) != null;
  }

  static JSObject? _asObject(JSAny? value) {
    if (value != null && value.isA<JSObject>()) {
      return value as JSObject;
    }
    return null;
  }

  static void _defaultWaitUntil<T>(FutureOr<T> Function() run) {
    Future<T>.sync(run);
  }
}
