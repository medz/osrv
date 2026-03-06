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
import 'host.dart';
import 'lifecycle_context.dart';
import 'request_bridge.dart';
import 'request_context.dart';
import 'response_bridge.dart';

const cloudflareRuntimeCapabilities = RuntimeCapabilities(
  streaming: false,
  websocket: false,
  fileSystem: false,
  backgroundTask: true,
  rawTcp: false,
  nodeCompat: false,
);

const cloudflareRuntimeInfo = RuntimeInfo(
  name: 'cloudflare',
  kind: 'entry',
);

const defaultCloudflareFetchName = '__osrv_fetch__';

void defineCloudflareFetch(
  Server server, {
  String name = defaultCloudflareFetchName,
}) {
  if (name.trim().isEmpty) {
    throw ArgumentError.value(
      name,
      'name',
      'Cloudflare fetch export name must not be empty.',
    );
  }

  globalContext.setProperty(
    name.toJS,
    _createCloudflareFetchExport(server),
  );
}

JSExportedDartFunction _createCloudflareFetchExport(
  Server server,
) {
  final handler = _CloudflareFetchHandler(server);
  JSPromise<web.Response> fetch(
    web.Request request, [
    JSObject? env,
    CloudflareExecutionContext? context,
  ]) => handler.handle(request, env, context).toJS;

  return fetch.toJS;
}

final class _CloudflareFetchHandler {
  _CloudflareFetchHandler(this._server);

  final Server _server;
  Future<void>? _startOperation;

  Future<void> _ensureStarted(
    CloudflareServerLifecycleContext context,
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
    web.Request request, [
    JSObject? env,
    CloudflareExecutionContext? context,
  ]) async {
    final extension = CloudflareRuntimeExtension(
      env: env,
      context: context,
      request: request,
    );
    final lifecycleContext = CloudflareServerLifecycleContext(
      runtime: cloudflareRuntimeInfo,
      capabilities: cloudflareRuntimeCapabilities,
      extension: extension,
    );
    final requestContext = CloudflareRequestContext(
      runtime: cloudflareRuntimeInfo,
      capabilities: cloudflareRuntimeCapabilities,
      extension: extension,
    );

    try {
      await _ensureStarted(lifecycleContext);
      final htRequest = await cloudflareRequestToHtRequest(request);
      final response = await _server.fetch(htRequest, requestContext);
      return cloudflareResponseFromHtResponse(response);
    } catch (error, stackTrace) {
      if (_server.onError != null) {
        final handled = await _server.onError!(
          error,
          stackTrace,
          lifecycleContext,
        );
        if (handled != null) {
          return cloudflareResponseFromHtResponse(handled);
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
