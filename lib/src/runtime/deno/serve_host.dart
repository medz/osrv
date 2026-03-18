// ignore_for_file: public_member_api_docs

@JS()
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:ht/ht.dart' show Request, Response, ResponseInit;
import 'package:web/web.dart' as web;

import '../../core/capabilities.dart';
import '../../core/errors.dart';
import '../../core/request_context.dart';
import '../../core/runtime.dart';
import '../../core/server.dart';
import '../../core/websocket.dart';
import '../_internal/js/web_response_bridge.dart';
import '../_internal/server/error_handler.dart';
import '../_internal/server/runtime_handle.dart';
import '../_internal/server/shutdown_coordinator.dart';
import 'extension.dart';
import 'interop.dart';
import 'preflight.dart';
import 'request_host.dart';
import 'server_web_socket.dart';
import 'websocket_request.dart';

Future<Runtime> serveDenoRuntimeHost(
  Server server,
  DenoRuntimePreflight preflight,
) async {
  final deno = preflight.extension.deno;
  if (deno == null) {
    throw preflight.toUnsupportedError();
  }

  final coordinator = ShutdownCoordinator();
  final startup = Completer<void>();
  unawaited(startup.future.catchError((Object _, StackTrace _) {}));
  final activeSockets = <DenoServerWebSocketAdapter>{};

  final runtimeInfo = const RuntimeInfo(name: 'deno', kind: 'server');
  late final DenoHttpServerHost hostServer;
  late final DenoRuntimeExtension lifecycleExtension;
  late final ServerLifecycleContext lifecycleContext;

  JSPromise<web.Response> fetch(web.Request request) {
    final operation = () async {
      try {
        await startup.future;
      } catch (_) {
        return _denoStartupFailureResponse();
      }

      return _handleDenoRequest(
        server: server,
        runtimeInfo: runtimeInfo,
        capabilities: preflight.capabilities,
        deno: deno,
        hostServer: hostServer,
        request: request,
        onWaitUntil: coordinator.trackTask,
        lifecycleContext: lifecycleContext,
        activeSockets: activeSockets,
      );
    }();
    coordinator.trackRequest(operation);
    return operation.toJS;
  }

  try {
    hostServer = denoServe(
      deno,
      host: preflight.host,
      port: preflight.port,
      handler: fetch.toJS,
    );
  } catch (error) {
    throw RuntimeStartupError(
      'Failed to bind deno runtime on ${preflight.host}:${preflight.port}.',
      error,
    );
  }

  lifecycleExtension = DenoRuntimeExtension(deno: deno, server: hostServer);
  lifecycleContext = ServerLifecycleContext(
    runtime: runtimeInfo,
    capabilities: preflight.capabilities,
    extension: lifecycleExtension,
  );

  try {
    if (server.onStart != null) {
      await server.onStart!(lifecycleContext);
    }
    startup.complete();
  } catch (error) {
    if (!startup.isCompleted) {
      startup.completeError(error);
    }
    try {
      await shutdownDenoServer(hostServer);
    } finally {
      await denoServerFinished(hostServer);
    }
    throw RuntimeStartupError('Failed to start deno runtime.', error);
  }

  final runtimeUrl = Uri(
    scheme: 'http',
    host: denoServerHostname(hostServer),
    port: denoServerPort(hostServer),
  );

  return ServerRuntimeHandle(
    info: runtimeInfo,
    capabilities: preflight.capabilities,
    closed: coordinator.closed,
    url: runtimeUrl,
    onClose: () async {
      final shutdown = shutdownDenoServer(hostServer);
      try {
        await coordinator.stop(
          onStop: () async {
            await _closeActiveDenoWebSockets(activeSockets);
            if (server.onStop != null) {
              await server.onStop!(lifecycleContext);
            }
          },
        );
      } finally {
        await shutdown;
        await denoServerFinished(hostServer);
      }
      await coordinator.closed;
    },
  );
}

Future<web.Response> _handleDenoRequest({
  required Server server,
  required RuntimeInfo runtimeInfo,
  required RuntimeCapabilities capabilities,
  required DenoGlobal? deno,
  required DenoHttpServerHost? hostServer,
  required web.Request request,
  required void Function(Future<void> task) onWaitUntil,
  required ServerLifecycleContext lifecycleContext,
  required Set<DenoServerWebSocketAdapter> activeSockets,
}) async {
  final requestHost = denoRequestHostFromWebRequest(request);
  final extension = DenoRuntimeExtension(
    deno: deno,
    server: hostServer,
    request: requestHost,
  );
  final webSocket = DenoWebSocketRequest(request);
  final context = RequestContext(
    runtime: runtimeInfo,
    capabilities: capabilities,
    onWaitUntil: onWaitUntil,
    extension: extension,
    webSocket: webSocket,
  );

  try {
    final htRequest = Request(request);
    final htResponse = await server.fetch(htRequest, context);
    return await _responseFromDenoFetchOutcome(
      htResponse,
      deno: deno,
      request: request,
      webSocket: webSocket,
      trackFuture: onWaitUntil,
      activeSockets: activeSockets,
    );
  } catch (error, stackTrace) {
    final handled = await handleServerError(
      server: server,
      error: error,
      stackTrace: stackTrace,
      context: lifecycleContext,
    );
    return await _responseFromDenoFetchOutcome(
      _sanitizeDenoErrorResponse(handled, webSocket: webSocket),
      deno: deno,
      request: request,
      webSocket: webSocket,
      trackFuture: onWaitUntil,
      activeSockets: activeSockets,
    );
  }
}

Future<web.Response> _responseFromDenoFetchOutcome(
  Response response, {
  required DenoGlobal? deno,
  required web.Request request,
  required DenoWebSocketRequest webSocket,
  required void Function(Future<void> task) trackFuture,
  required Set<DenoServerWebSocketAdapter> activeSockets,
}) async {
  final upgrade = webSocket.takeAcceptedUpgrade(response);
  if (upgrade != null) {
    if (deno == null) {
      return _denoUpgradeFailureResponse();
    }

    final result = denoUpgradeWebSocket(
      deno,
      request,
      protocol: upgrade.protocol,
    );
    final adapter = DenoServerWebSocketAdapter(result.socket);
    activeSockets.add(adapter);

    trackFuture(
      adapter.closed.whenComplete(() {
        activeSockets.remove(adapter);
      }),
    );

    final session = _runDenoWebSocketSession(adapter, upgrade.handler);
    trackFuture(session);
    unawaited(session);
    return result.response;
  }

  if (response.status == 101) {
    throw StateError(
      'Raw 101 responses are reserved for websocket upgrades. Use '
      'context.webSocket.accept(...) to accept an upgrade.',
    );
  }

  return webResponseFromHtResponse(response);
}

Future<void> _runDenoWebSocketSession(
  DenoServerWebSocketAdapter socket,
  WebSocketHandler handler,
) async {
  try {
    await socket.opened;
    await handler(socket);
  } catch (error, stackTrace) {
    try {
      await socket.close(1011, 'Internal Server Error');
    } catch (_) {}

    Zone.current.handleUncaughtError(error, stackTrace);
  }
}

Future<void> _closeActiveDenoWebSockets(
  Set<DenoServerWebSocketAdapter> activeSockets,
) async {
  final sockets = List<DenoServerWebSocketAdapter>.of(activeSockets);
  for (final socket in sockets) {
    try {
      await socket.close(1001, 'Runtime shutdown');
    } catch (_) {}
  }
}

Response _sanitizeDenoErrorResponse(
  Response response, {
  required DenoWebSocketRequest webSocket,
}) {
  if (response.status != 101 || webSocket.hasAcceptedUpgrade(response)) {
    return response;
  }

  return Response('Internal Server Error', const ResponseInit(status: 500));
}

web.Response _denoStartupFailureResponse() {
  return web.Response(
    'Service Unavailable'.toJS,
    web.ResponseInit(status: 503, statusText: 'Service Unavailable'),
  );
}

web.Response _denoUpgradeFailureResponse() {
  return webResponseFromHtResponse(
    Response('WebSocket upgrade failed', const ResponseInit(status: 500)),
  );
}
