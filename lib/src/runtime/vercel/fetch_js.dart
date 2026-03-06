@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../../core/capabilities.dart';
import '../../core/runtime.dart';
import '../../core/server.dart';
import 'extension.dart';
import 'functions.dart';
import 'host.dart';
import 'lifecycle_context.dart';
import 'request_bridge.dart';
import 'request_context.dart';
import 'response_bridge.dart';

const vercelRuntimeCapabilities = RuntimeCapabilities(
  streaming: true,
  websocket: false,
  fileSystem: true,
  backgroundTask: true,
  rawTcp: false,
  nodeCompat: true,
);

const vercelRuntimeInfo = RuntimeInfo(
  name: 'vercel',
  kind: 'entry',
);

const defaultVercelFetchName = '__osrv_fetch__';

void defineVercelFetch(
  Server server, {
  String name = defaultVercelFetchName,
}) {
  if (name.trim().isEmpty) {
    throw ArgumentError.value(
      name,
      'name',
      'Vercel fetch export name must not be empty.',
    );
  }

  globalContext.setProperty(
    name.toJS,
    _createVercelFetchExport(server),
  );
}

JSExportedDartFunction _createVercelFetchExport(
  Server server,
) {
  final handler = _VercelFetchHandler(server);
  JSPromise<web.Response> fetch(
    web.Request request,
  ) => handler.handle(request).toJS;

  return fetch.toJS;
}

final class _VercelFetchHandler {
  _VercelFetchHandler(this._server);

  final Server _server;
  Future<void>? _startOperation;

  Future<void> _ensureStarted(
    VercelServerLifecycleContext context,
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
    web.Request request,
  ) async {
    final resolvedHelpers = await loadVercelFunctionHelpers();
    final extension = VercelRuntimeExtension<VercelFunctionHelpersHost,
        web.Request>(
      functions: createVercelFunctions(resolvedHelpers),
      helpers: resolvedHelpers,
      request: request,
      env: vercelGetEnv(resolvedHelpers),
      geolocation: vercelGeolocation(resolvedHelpers, request),
      ipAddress: vercelIpAddress(resolvedHelpers, request),
    );
    final lifecycleContext = VercelServerLifecycleContext(
      runtime: vercelRuntimeInfo,
      capabilities: vercelRuntimeCapabilities,
      extension: extension,
    );
    final requestContext = VercelRequestContext(
      runtime: vercelRuntimeInfo,
      capabilities: vercelRuntimeCapabilities,
      extension: extension,
    );

    try {
      await _ensureStarted(lifecycleContext);
      final htRequest = vercelRequestToHtRequest(request);
      final response = await _server.fetch(htRequest, requestContext);
      return vercelResponseFromHtResponse(response);
    } catch (error, stackTrace) {
      if (_server.onError != null) {
        final handled = await _server.onError!(
          error,
          stackTrace,
          lifecycleContext,
        );
        if (handled != null) {
          return vercelResponseFromHtResponse(handled);
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
