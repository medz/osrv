@JS()
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../core/capabilities.dart';
import '../../core/runtime.dart';
import '../../core/server.dart';
import '../_internal/js/fetch_handler.dart';
import '../_internal/js/web_request_bridge.dart';
import '../_internal/js/web_response_bridge.dart';
import 'extension.dart';
import 'host.dart';
import 'lifecycle_context.dart';
import 'request_context.dart';

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

JSExportedDartFunction createCloudflareFetchEntry(
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
          toHtRequest: htRequestFromWebRequest,
          fromHtResponse: webResponseFromHtResponse,
        )
        .toJS;
  }

  return fetch.toJS;
}
