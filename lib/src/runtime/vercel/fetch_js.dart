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

const defaultVercelFetchName = defaultFetchEntryName;

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

  defineFetchEntry(
    _createVercelFetchExport(server),
    name: name,
  );
}

JSExportedDartFunction _createVercelFetchExport(
  Server server,
) {
  final handler = JsEntryFetchHandler(server);
  JSPromise<web.Response> fetch(
    web.Request request,
  ) {
    final operation = () async {
      final resolvedHelpers = await loadVercelFunctionHelpers();
      final extension = VercelRuntimeExtension<web.Request>(
        functions: createVercelFunctions(
          resolvedHelpers,
          request,
        ),
        request: request,
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

      return handler.handle(
        request,
        lifecycleContext: lifecycleContext,
        requestContext: requestContext,
        toHtRequest: vercelRequestToHtRequest,
        fromHtResponse: vercelResponseFromHtResponse,
      );
    }();

    return operation.toJS;
  }

  return fetch.toJS;
}
