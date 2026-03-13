// ignore_for_file: public_member_api_docs

@JS()
library;

import 'dart:js_interop';
import 'package:ht/ht.dart' show Request;
import 'package:web/web.dart' as web;

import '../../core/capabilities.dart';
import '../../core/request_context.dart';
import '../../core/runtime.dart';
import '../../core/server.dart';
import '../_internal/js/fetch_handler.dart';
import '../_internal/js/web_response_bridge.dart';
import 'extension.dart';
import 'functions.dart';
import 'host.dart';

const vercelRuntimeCapabilities = RuntimeCapabilities(
  streaming: true,
  websocket: false,
  fileSystem: true,
  backgroundTask: true,
  rawTcp: false,
  nodeCompat: true,
);

const vercelRuntimeInfo = RuntimeInfo(name: 'vercel', kind: 'entry');

JSExportedDartFunction createVercelFetchEntry(Server server) {
  final handler = JsEntryFetchHandler(server);
  JSPromise<web.Response> fetch(web.Request request) {
    final operation = () async {
      final resolvedHelpers = await loadVercelFunctionHelpers();
      final extension = VercelRuntimeExtension<web.Request>(
        functions: createVercelFunctions(resolvedHelpers, request),
        request: request,
      );
      final lifecycleContext = ServerLifecycleContext(
        runtime: vercelRuntimeInfo,
        capabilities: vercelRuntimeCapabilities,
        extension: extension,
      );
      final requestContext = RequestContext(
        runtime: vercelRuntimeInfo,
        capabilities: vercelRuntimeCapabilities,
        onWaitUntil: (task) {
          extension.functions?.waitUntil(task);
        },
        extension: extension,
      );

      return handler.handle(
        request,
        lifecycleContext: lifecycleContext,
        requestContext: requestContext,
        toHtRequest: (request) => Request(request),
        fromHtResponse: webResponseFromHtResponse,
      );
    }();

    return operation.toJS;
  }

  return fetch.toJS;
}
