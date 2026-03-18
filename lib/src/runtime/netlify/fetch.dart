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
import 'host.dart';

const _netlifyBaseRuntimeCapabilities = RuntimeCapabilities(
  streaming: true,
  websocket: false,
  fileSystem: true,
  backgroundTask: false,
  rawTcp: false,
  nodeCompat: true,
);

const netlifyRuntimeInfo = RuntimeInfo(name: 'netlify', kind: 'entry');

JSExportedDartFunction createNetlifyFetchEntry(Server server) {
  final handler = JsEntryFetchHandler(server);
  JSPromise<web.Response> fetch(web.Request request, [JSObject? context]) {
    final operation = () async {
      final netlifyContext = context == null ? null : NetlifyContext(context);
      final requestCapabilities = _requestCapabilities(netlifyContext);
      final startupContext = ServerLifecycleContext(
        runtime: netlifyRuntimeInfo,
        capabilities: _netlifyBaseRuntimeCapabilities,
        extension: const NetlifyRuntimeExtension<web.Request>(),
      );
      final extension = NetlifyRuntimeExtension<web.Request>(
        context: netlifyContext,
        request: request,
      );
      final lifecycleContext = ServerLifecycleContext(
        runtime: netlifyRuntimeInfo,
        capabilities: requestCapabilities,
        extension: extension,
      );
      final requestContext = RequestContext(
        runtime: netlifyRuntimeInfo,
        capabilities: requestCapabilities,
        onWaitUntil: (task) {
          netlifyWaitUntil(netlifyContext, task);
        },
        extension: extension,
      );

      await handler.ensureStarted(startupContext);
      return handler.handle(
        request,
        lifecycleContext: lifecycleContext,
        requestContext: requestContext,
        toHtRequest: (request) => Request(request),
        fromHtResponse: webResponseFromHtResponseRejectingRaw101,
      );
    }();

    return operation.toJS;
  }

  return fetch.toJS;
}

RuntimeCapabilities _requestCapabilities(NetlifyContext? context) {
  return RuntimeCapabilities(
    streaming: _netlifyBaseRuntimeCapabilities.streaming,
    websocket: _netlifyBaseRuntimeCapabilities.websocket,
    fileSystem: _netlifyBaseRuntimeCapabilities.fileSystem,
    backgroundTask: netlifySupportsBackgroundTask(context),
    rawTcp: _netlifyBaseRuntimeCapabilities.rawTcp,
    nodeCompat: _netlifyBaseRuntimeCapabilities.nodeCompat,
  );
}
