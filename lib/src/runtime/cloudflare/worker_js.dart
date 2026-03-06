@JS()
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../core/capabilities.dart';
import '../../core/runtime.dart';
import '../../core/server.dart';
import '../_internal/js/fetch_entry.dart';
import '../_internal/js/fetch_handler.dart';
import 'extension.dart';
import 'host.dart';
import 'lifecycle_context.dart';
import 'request_bridge.dart';
import 'request_context.dart';
import 'response_bridge.dart';

const cloudflareRuntimeCapabilities = RuntimeCapabilities(
  streaming: true,
  websocket: false,
  fileSystem: false,
  backgroundTask: true,
  rawTcp: false,
  nodeCompat: true,
);

const cloudflareRuntimeInfo = RuntimeInfo(
  name: 'cloudflare',
  kind: 'entry',
);

const defaultCloudflareFetchName = defaultFetchEntryName;

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

  defineFetchEntry(
    _createCloudflareFetchExport(server),
    name: name,
  );
}

JSExportedDartFunction _createCloudflareFetchExport(
  Server server,
) {
  final handler = JsEntryFetchHandler(server);
  JSPromise<web.Response> fetch(
    web.Request request, [
    JSObject? env,
    CloudflareExecutionContext? context,
  ]) {
    final extension = CloudflareRuntimeExtension<JSObject, web.Request>(
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

    return handler
        .handle(
          request,
          lifecycleContext: lifecycleContext,
          requestContext: requestContext,
          toHtRequest: cloudflareRequestToHtRequest,
          fromHtResponse: cloudflareResponseFromHtResponse,
        )
        .toJS;
  }

  return fetch.toJS;
}
