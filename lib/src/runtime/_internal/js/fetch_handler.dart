import 'dart:async';
import 'dart:js_interop';

import 'package:ht/ht.dart' show Request, Response;
import 'package:web/web.dart' as web;

import '../../../core/request_context.dart';
import '../../../core/server.dart';

final class JsEntryFetchHandler {
  JsEntryFetchHandler(this._server);

  final Server _server;
  Future<void>? _startOperation;

  Future<void> ensureStarted(
    ServerLifecycleContext context,
  ) {
    final existing = _startOperation;
    if (existing != null) {
      return existing;
    }

    final operation = () async {
      if (_server.onStart != null) {
        await _server.onStart!(context);
      }
    }();
    _startOperation = operation;
    return operation;
  }

  Future<web.Response> handle(
    web.Request request, {
    required ServerLifecycleContext lifecycleContext,
    required RequestContext requestContext,
    required Request Function(web.Request request) toHtRequest,
    required web.Response Function(Response response) fromHtResponse,
  }) async {
    try {
      await ensureStarted(lifecycleContext);
      final htRequest = toHtRequest(request);
      final response = await _server.fetch(htRequest, requestContext);
      return fromHtResponse(response);
    } catch (error, stackTrace) {
      if (_server.onError != null) {
        final handled = await _server.onError!(
          error,
          stackTrace,
          lifecycleContext,
        );
        if (handled != null) {
          return fromHtResponse(handled);
        }
      }

      return web.Response(
        'Internal Server Error'.toJS,
        web.ResponseInit(
          status: 500,
          statusText: 'Internal Server Error',
        ),
      );
    }
  }
}
