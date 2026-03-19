// ignore_for_file: public_member_api_docs

@JS()
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:ht/ht.dart' show Request, Response, ResponseInit;
import 'package:web/web.dart' as web;

import '../../core/capabilities.dart';
import '../../core/request_context.dart';
import '../../core/runtime.dart';
import '../../core/server.dart';
import '../../core/websocket.dart';
import '../_internal/js/fetch_handler.dart';
import '../_internal/js/web_response_bridge.dart';
import 'extension.dart';
import 'host.dart';
import 'server_web_socket.dart';
import 'websocket_request.dart';

const cloudflareRuntimeCapabilities = RuntimeCapabilities(
  streaming: true,
  websocket: true,
  fileSystem: false,
  backgroundTask: true,
  rawTcp: false,
  nodeCompat: true,
);

const cloudflareRuntimeInfo = RuntimeInfo(name: 'cloudflare', kind: 'entry');

JSExportedDartFunction createCloudflareFetchEntry(Server server) {
  final handler = JsEntryFetchHandler(server);
  JSPromise<web.Response> fetch(
    web.Request request, [
    JSObject? env,
    CloudflareExecutionContext? context,
  ]) {
    final operation = () async {
      final extension = CloudflareRuntimeExtension<JSObject, web.Request>(
        env: env,
        context: context,
        request: request,
      );
      final lifecycleContext = ServerLifecycleContext(
        runtime: cloudflareRuntimeInfo,
        capabilities: cloudflareRuntimeCapabilities,
        extension: extension,
      );
      final webSocket = CloudflareWebSocketRequest(request);
      final requestContext = RequestContext(
        runtime: cloudflareRuntimeInfo,
        capabilities: cloudflareRuntimeCapabilities,
        onWaitUntil: (task) {
          cloudflareWaitUntil(context, task);
        },
        extension: extension,
        webSocket: webSocket,
      );

      try {
        await handler.ensureStarted(lifecycleContext);
        final response = await server.fetch(Request(request), requestContext);
        return _responseFromCloudflareFetchOutcome(
          response,
          webSocket: webSocket,
        );
      } catch (error, stackTrace) {
        if (server.onError != null) {
          try {
            final handled = await server.onError!(
              error,
              stackTrace,
              requestContext,
            );
            if (handled != null) {
              return _responseFromCloudflareFetchOutcome(
                _sanitizeCloudflareErrorResponse(handled, webSocket: webSocket),
                webSocket: webSocket,
              );
            }
          } catch (_) {
            // Fall back to the default 500 response when user-provided onError
            // handling also fails.
          }
        }

        return web.Response(
          'Internal Server Error'.toJS,
          web.ResponseInit(status: 500, statusText: 'Internal Server Error'),
        );
      }
    }();

    return operation.toJS;
  }

  return fetch.toJS;
}

web.Response _responseFromCloudflareFetchOutcome(
  Response response, {
  required CloudflareWebSocketRequest webSocket,
}) {
  final accepted = webSocket.takeAcceptedUpgrade(response);
  if (accepted != null) {
    final pair = cloudflareCreateWebSocketPair();
    if (pair == null) {
      return webResponseFromHtResponse(
        Response('WebSocket upgrade failed', const ResponseInit(status: 500)),
      );
    }

    final protocol = accepted.protocol;
    cloudflareWebSocketAccept(pair.server);

    final socket = CloudflareServerWebSocketAdapter(
      pair.server,
      protocol: protocol ?? cloudflareWebSocketProtocol(pair.server),
    );
    final session = _runCloudflareWebSocketSession(socket, accepted.handler);
    unawaited(session);

    return cloudflareUpgradeResponse(pair.client, protocol: protocol);
  }

  if (response.status == 101) {
    throw StateError(
      'Raw 101 responses are reserved for websocket upgrades. Use '
      'context.webSocket.accept(...) to accept an upgrade.',
    );
  }

  return webResponseFromHtResponse(response);
}

Future<void> _runCloudflareWebSocketSession(
  CloudflareServerWebSocketAdapter socket,
  WebSocketHandler handler,
) async {
  try {
    await handler(socket);
  } catch (error, stackTrace) {
    try {
      await socket.close(1011, 'Internal Server Error');
    } catch (_) {}

    Zone.current.handleUncaughtError(error, stackTrace);
  }
}

Response _sanitizeCloudflareErrorResponse(
  Response response, {
  required CloudflareWebSocketRequest webSocket,
}) {
  if (response.status != 101 || webSocket.hasAcceptedUpgrade(response)) {
    return response;
  }

  return Response('Internal Server Error', const ResponseInit(status: 500));
}
