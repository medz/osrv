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

Future<Runtime> serveBunRuntimeHost(
  Server server,
  BunRuntimePreflight preflight,
) async {
  final bun = preflight.extension.bun;
  if (bun == null) {
    throw preflight.toUnsupportedError();
  }

  final coordinator = ShutdownCoordinator();
  final startup = Completer<void>();
  unawaited(startup.future.catchError((Object _, StackTrace _) {}));

  final runtimeInfo = const RuntimeInfo(name: 'bun', kind: 'server');
  final tokenSequence = _BunWebSocketTokenSequence();
  final pendingUpgrades = <int, BunAcceptedWebSocketUpgrade>{};
  final activeSockets = <int, _BunActiveWebSocketSession>{};
  var isShuttingDown = false;

  late final BunServerHost hostServer;
  late final BunRuntimeExtension lifecycleExtension;
  late final ServerLifecycleContext lifecycleContext;

  void open(BunServerWebSocketHost socket) {
    final token = bunServerWebSocketToken(socket);
    final upgrade = token == null ? null : pendingUpgrades.remove(token);
    if (token == null || upgrade == null) {
      bunServerWebSocketClose(
        socket,
        code: 1011,
        reason: 'Missing websocket upgrade state.',
      );
      return;
    }

    final adapter = BunServerWebSocketAdapter(
      socket,
      protocol: upgrade.protocol ?? '',
    );
    final session = _BunActiveWebSocketSession(socket, adapter);
    activeSockets[token] = session;
    coordinator.trackConnection(session.closed);

    final operation = _runBunWebSocketSession(
      handler: upgrade.handler,
      session: session,
    );
    coordinator.trackTask(operation);
    unawaited(operation);
  }

  void message(BunServerWebSocketHost socket, JSAny message) {
    final token = bunServerWebSocketToken(socket);
    if (token == null) {
      return;
    }

    activeSockets[token]?.adapter.addMessage(message);
  }

  void close(BunServerWebSocketHost socket, JSNumber? code, JSString? reason) {
    final token = bunServerWebSocketToken(socket);
    if (token == null) {
      return;
    }

    activeSockets.remove(token)?.close(code?.toDartInt, reason?.toDart);
  }

  void error(BunServerWebSocketHost socket, JSAny? error) {
    final token = bunServerWebSocketToken(socket);
    if (token == null) {
      return;
    }

    final message = _describeBunWebSocketError(error);
    final session = activeSockets.remove(token);
    if (session == null) {
      return;
    }

    session.close(1011, message);
    Zone.current.handleUncaughtError(StateError(message), StackTrace.current);
  }

  void drain(BunServerWebSocketHost socket) {
    socket;
  }

  final websocketHandlers = bunWebSocketHandlers(
    open: open.toJS,
    message: message.toJS,
    close: close.toJS,
    error: error.toJS,
    drain: drain.toJS,
  );

  JSPromise<JSAny?> fetch(web.Request request, [JSAny? serverHost]) {
    serverHost;
    final requestHost = bunRequestHostFromWebRequest(request);
    final operation = () async {
      await startup.future;
      if (isShuttingDown) {
        return _bunShuttingDownResponse() as JSAny?;
      }

      final response = await _handleBunRequest(
        server: server,
        runtimeInfo: runtimeInfo,
        capabilities: preflight.capabilities,
        bun: bun,
        hostServer: hostServer,
        request: request,
        requestHost: requestHost,
        onWaitUntil: coordinator.trackTask,
        lifecycleContext: lifecycleContext,
        tokenSequence: tokenSequence,
        pendingUpgrades: pendingUpgrades,
      );
      return response as JSAny?;
    }();
    coordinator.trackRequest(operation);
    return operation.toJS;
  }

  try {
    hostServer = bunServe(
      bun,
      host: preflight.host,
      port: preflight.port,
      fetch: fetch.toJS,
      websocket: websocketHandlers,
    );
  } catch (error) {
    throw RuntimeStartupError(
      'Failed to bind bun runtime on ${preflight.host}:${preflight.port}.',
      error,
    );
  }

  lifecycleExtension = BunRuntimeExtension(bun: bun, server: hostServer);
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
    await stopBunServer(hostServer, force: true);
    throw RuntimeStartupError('Failed to start bun runtime.', error);
  }

  final runtimeUrl = Uri(
    scheme: 'http',
    host: preflight.host,
    port: bunServerPort(hostServer) ?? preflight.port,
  );

  return ServerRuntimeHandle(
    info: runtimeInfo,
    capabilities: preflight.capabilities,
    closed: coordinator.closed,
    url: runtimeUrl,
    onClose: () async {
      isShuttingDown = true;
      final stop = coordinator.stop(
        onStop: () async {
          await _stopBunRuntime(
            server: server,
            lifecycleContext: lifecycleContext,
            activeSockets: activeSockets,
          );
        },
      );

      try {
        await stopBunServer(hostServer);
      } finally {
        await stop;
      }

      await coordinator.closed;
    },
  );
}

Future<web.Response?> _handleBunRequest({
  required Server server,
  required RuntimeInfo runtimeInfo,
  required RuntimeCapabilities capabilities,
  required BunGlobal? bun,
  required BunServerHost? hostServer,
  required web.Request request,
  required BunRequestHost? requestHost,
  required void Function(Future<void> task) onWaitUntil,
  required ServerLifecycleContext lifecycleContext,
  required _BunWebSocketTokenSequence tokenSequence,
  required Map<int, BunAcceptedWebSocketUpgrade> pendingUpgrades,
}) async {
  final extension = BunRuntimeExtension(
    bun: bun,
    server: hostServer,
    request: requestHost,
  );
  final webSocket = BunWebSocketRequest(request);
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
    return _responseFromBunFetchOutcome(
      htResponse,
      request: request,
      hostServer: hostServer,
      webSocket: webSocket,
      tokenSequence: tokenSequence,
      pendingUpgrades: pendingUpgrades,
    );
  } catch (error, stackTrace) {
    final handled = await handleServerError(
      server: server,
      error: error,
      stackTrace: stackTrace,
      context: lifecycleContext,
    );
    return _responseFromBunFetchOutcome(
      _sanitizeBunErrorResponse(handled, webSocket: webSocket),
      request: request,
      hostServer: hostServer,
      webSocket: webSocket,
      tokenSequence: tokenSequence,
      pendingUpgrades: pendingUpgrades,
    );
  }
}

web.Response? _responseFromBunFetchOutcome(
  Response response, {
  required web.Request request,
  required BunServerHost? hostServer,
  required BunWebSocketRequest webSocket,
  required _BunWebSocketTokenSequence tokenSequence,
  required Map<int, BunAcceptedWebSocketUpgrade> pendingUpgrades,
}) {
  final upgrade = webSocket.takeAcceptedUpgrade(response);
  if (upgrade != null) {
    if (hostServer == null) {
      return _bunUpgradeFailureResponse();
    }

    final token = tokenSequence.next();
    pendingUpgrades[token] = upgrade;
    final upgraded = bunServerUpgrade(
      hostServer,
      request,
      token: token,
      protocol: upgrade.protocol,
    );

    if (upgraded) {
      return null;
    }

    pendingUpgrades.remove(token);
    return _bunUpgradeFailureResponse();
  }

  if (response.status == 101) {
    throw StateError(
      'Raw 101 responses are reserved for websocket upgrades. Use '
      'context.webSocket.accept(...) to accept an upgrade.',
    );
  }

  return webResponseFromHtResponse(response);
}

web.Response _bunUpgradeFailureResponse() {
  return webResponseFromHtResponse(
    Response('WebSocket upgrade failed', const ResponseInit(status: 500)),
  );
}

web.Response _bunShuttingDownResponse() {
  return webResponseFromHtResponse(
    Response('Service Unavailable', const ResponseInit(status: 503)),
  );
}

Future<void> _runBunWebSocketSession({
  required WebSocketHandler handler,
  required _BunActiveWebSocketSession session,
}) async {
  try {
    await handler(session.adapter);
  } catch (error, stackTrace) {
    try {
      await session.adapter.close(1011, 'Internal Server Error');
    } catch (_) {}

    Zone.current.handleUncaughtError(error, stackTrace);
  }
}

Future<void> _stopBunRuntime({
  required Server server,
  required ServerLifecycleContext lifecycleContext,
  required Map<int, _BunActiveWebSocketSession> activeSockets,
}) async {
  await _closeActiveBunWebSockets(activeSockets);

  if (server.onStop != null) {
    await server.onStop!(lifecycleContext);
  }
}

Future<void> _closeActiveBunWebSockets(
  Map<int, _BunActiveWebSocketSession> activeSockets,
) async {
  final sessions = List<_BunActiveWebSocketSession>.of(activeSockets.values);
  for (final session in sessions) {
    try {
      await session.adapter.close(1001, 'Runtime shutdown');
    } catch (_) {}
  }
}

Response _sanitizeBunErrorResponse(
  Response response, {
  required BunWebSocketRequest webSocket,
}) {
  if (response.status != 101 || webSocket.hasAcceptedUpgrade(response)) {
    return response;
  }

  return Response('Internal Server Error', const ResponseInit(status: 500));
}

String _describeBunWebSocketError(JSAny? error) {
  final value = error?.dartify();
  return value?.toString() ?? 'Unknown Bun websocket error.';
}

final class _BunWebSocketTokenSequence {
  int _value = 0;

  int next() => _value++;
}

final class _BunActiveWebSocketSession {
  _BunActiveWebSocketSession(this.socket, this.adapter);

  final BunServerWebSocketHost socket;
  final BunServerWebSocketAdapter adapter;
  final Completer<void> _closed = Completer<void>();

  Future<void> get closed => _closed.future;

  void close(int? code, String? reason) {
    adapter.closeFromHost(code, reason);
    if (!_closed.isCompleted) {
      _closed.complete();
    }
  }
}
