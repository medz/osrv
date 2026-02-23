import 'dart:async';

import 'package:ht/ht.dart';

import '../request.dart';
import '../types/index.dart';
import 'error_handler.dart';

final class RequestDispatcher {
  RequestDispatcher({
    required this.server,
    required FetchHandler fetch,
    required ErrorHandler? error,
    required Iterable<Middleware> middleware,
    required Iterable<ServerPlugin> plugins,
  }) : _fetch = fetch,
       _error = error,
       _middleware = List<Middleware>.unmodifiable(middleware),
       _plugins = List<ServerPlugin>.unmodifiable(plugins);

  final ServerHandle server;
  final FetchHandler _fetch;
  final ErrorHandler? _error;
  final List<Middleware> _middleware;
  final List<ServerPlugin> _plugins;

  Future<Response> dispatch(ServerRequest request) async {
    try {
      await _runPluginRequest(request);
      final response = await _runPipeline(0, request);
      await _runPluginResponse(request, response);
      return response;
    } catch (error, stackTrace) {
      await _runPluginError(request, error, stackTrace);
      return runErrorHandler(
        request: request,
        error: error,
        stackTrace: stackTrace,
        errorHandler: _error,
      );
    }
  }

  Future<Response> _runPipeline(int index, ServerRequest request) {
    if (index >= _middleware.length) {
      return Future<Response>.value(_fetch(request));
    }

    final middleware = _middleware[index];
    var nextCalled = false;

    Future<Response> next(ServerRequest nextRequest) {
      if (nextCalled) {
        throw StateError('Middleware called next() more than once.');
      }
      nextCalled = true;
      return _runPipeline(index + 1, nextRequest);
    }

    return Future<Response>.value(middleware(request, next));
  }

  Future<void> _runPluginRequest(ServerRequest request) async {
    for (final plugin in _plugins) {
      await Future<void>.value(plugin.onRequest(server, request));
    }
  }

  Future<void> _runPluginResponse(
    ServerRequest request,
    Response response,
  ) async {
    for (final plugin in _plugins) {
      await Future<void>.value(plugin.onResponse(server, request, response));
    }
  }

  Future<void> _runPluginError(
    ServerRequest request,
    Object error,
    StackTrace stackTrace,
  ) async {
    for (final plugin in _plugins) {
      try {
        await Future<void>.value(
          plugin.onError(server, request, error, stackTrace),
        );
      } catch (_) {
        // Plugin error hooks are best-effort and must not shadow request errors.
      }
    }
  }
}
