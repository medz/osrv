// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:io';

import 'package:ht/ht.dart' show Request, Response, ResponseInit;
import 'package:web_socket/io_web_socket.dart' show IOWebSocket;

import '../../core/capabilities.dart';
import '../../core/errors.dart';
import '../../core/request_context.dart';
import '../../core/runtime.dart';
import '../../core/server.dart';
import '../../core/websocket.dart';
import '../_internal/server/error_handler.dart';
import '../_internal/server/runtime_handle.dart';
import '../_internal/server/shutdown_coordinator.dart';
import 'extension.dart';
import 'response_bridge.dart';
import 'websocket_request.dart';

const dartRuntimeCapabilities = RuntimeCapabilities(
  streaming: true,
  websocket: true,
  fileSystem: true,
  backgroundTask: true,
  rawTcp: true,
  nodeCompat: false,
);

Future<Runtime> serveDartRuntime(
  Server server, {
  String host = '127.0.0.1',
  int port = 3000,
  int backlog = 0,
  bool shared = false,
  bool v6Only = false,
}) async {
  _validateDartServeParameters(host: host, port: port, backlog: backlog);

  final httpServer = await _bindDartHttpServer(
    host: host,
    port: port,
    backlog: backlog,
    shared: shared,
    v6Only: v6Only,
  );

  final runtimeInfo = RuntimeInfo(name: 'dart', kind: 'server');
  final lifecycleExtension = DartRuntimeExtension(server: httpServer);
  final lifecycleContext = ServerLifecycleContext(
    runtime: runtimeInfo,
    capabilities: dartRuntimeCapabilities,
    extension: lifecycleExtension,
  );

  final coordinator = ShutdownCoordinator();
  final activeSockets = <WebSocket>{};

  try {
    if (server.onStart != null) {
      await server.onStart!(lifecycleContext);
    }
  } catch (error) {
    await httpServer.close(force: true);
    throw RuntimeStartupError('Failed to start dart runtime.', error);
  }

  unawaited(() async {
    try {
      await for (final request in httpServer) {
        final operation = _handleDartRequest(
          server: server,
          runtimeInfo: runtimeInfo,
          lifecycleContext: lifecycleContext,
          httpServer: httpServer,
          request: request,
          coordinator: coordinator,
          activeSockets: activeSockets,
        );
        coordinator.trackRequest(operation);
        unawaited(operation);
      }
    } finally {
      await coordinator.stop(
        onStop: () async {
          await _stopDartRuntime(
            server: server,
            lifecycleContext: lifecycleContext,
            activeSockets: activeSockets,
          );
        },
        waitForRequests: true,
      );
    }
  }());

  return ServerRuntimeHandle(
    info: runtimeInfo,
    capabilities: dartRuntimeCapabilities,
    closed: coordinator.closed,
    url: Uri(scheme: 'http', host: host, port: httpServer.port),
    onClose: () async {
      final stop = coordinator.stop(
        onStop: () async {
          await _stopDartRuntime(
            server: server,
            lifecycleContext: lifecycleContext,
            activeSockets: activeSockets,
          );
        },
        waitForRequests: true,
      );
      await httpServer.close();
      await stop;
      await coordinator.closed;
    },
  );
}

Future<void> _handleDartRequest({
  required Server server,
  required RuntimeInfo runtimeInfo,
  required ServerLifecycleContext lifecycleContext,
  required HttpServer httpServer,
  required HttpRequest request,
  required ShutdownCoordinator coordinator,
  required Set<WebSocket> activeSockets,
}) async {
  final requestExtension = DartRuntimeExtension(
    server: httpServer,
    request: request,
    response: request.response,
  );
  final webSocket = DartWebSocketRequest(request);
  final context = RequestContext(
    runtime: runtimeInfo,
    capabilities: dartRuntimeCapabilities,
    onWaitUntil: coordinator.trackTask,
    extension: requestExtension,
    webSocket: webSocket,
  );

  try {
    final htRequest = Request(request);
    final response = await server.fetch(htRequest, context);
    await _writeDartFetchResponse(
      response,
      request: request,
      webSocket: webSocket,
      coordinator: coordinator,
      activeSockets: activeSockets,
    );
  } catch (error, stackTrace) {
    final handled = await handleServerError(
      server: server,
      error: error,
      stackTrace: stackTrace,
      context: context,
      defaultStatus: HttpStatus.internalServerError,
    );
    await _writeDartFetchResponse(
      _sanitizeErrorResponse(handled, webSocket: webSocket),
      request: request,
      webSocket: webSocket,
      coordinator: coordinator,
      activeSockets: activeSockets,
    );
  }
}

Future<HttpServer> _bindDartHttpServer({
  required String host,
  required int port,
  required int backlog,
  required bool shared,
  required bool v6Only,
}) async {
  try {
    return await HttpServer.bind(
      host,
      port,
      backlog: backlog,
      shared: shared,
      v6Only: v6Only,
    );
  } catch (error) {
    throw RuntimeStartupError(
      'Failed to bind dart runtime on $host:$port.',
      error,
    );
  }
}

Future<void> _writeDartFetchResponse(
  Response response, {
  required HttpRequest request,
  required DartWebSocketRequest webSocket,
  required ShutdownCoordinator coordinator,
  required Set<WebSocket> activeSockets,
}) async {
  final upgrade = webSocket.takeAcceptedUpgrade(response);
  if (upgrade != null) {
    await _handleDartWebSocketUpgrade(
      request,
      upgrade: upgrade,
      coordinator: coordinator,
      activeSockets: activeSockets,
    );
    return;
  }

  if (response.status == HttpStatus.switchingProtocols) {
    throw StateError(
      'Raw 101 responses are reserved for websocket upgrades. '
      'Use context.webSocket?.accept(...) to accept an upgrade.',
    );
  }

  await writeHtResponseToDartHttpResponse(response, request.response);
}

Future<void> _handleDartWebSocketUpgrade(
  HttpRequest request, {
  required DartAcceptedWebSocketUpgrade upgrade,
  required ShutdownCoordinator coordinator,
  required Set<WebSocket> activeSockets,
}) async {
  final socket = await WebSocketTransformer.upgrade(
    request,
    protocolSelector: upgrade.protocol == null
        ? null
        : (_) => Future<String>.value(upgrade.protocol!),
  );

  activeSockets.add(socket);
  final connection = socket.done.whenComplete(() {
    activeSockets.remove(socket);
  });
  coordinator.trackConnection(connection);

  final session = _runDartWebSocketSession(socket, upgrade.handler);
  coordinator.trackTask(session);
  unawaited(session);
}

Future<void> _runDartWebSocketSession(
  WebSocket socket,
  WebSocketHandler handler,
) async {
  try {
    await handler(IOWebSocket.fromWebSocket(socket));
  } catch (error, stackTrace) {
    try {
      await socket.close(
        WebSocketStatus.internalServerError,
        'Internal Server Error',
      );
    } catch (_) {}

    Zone.current.handleUncaughtError(error, stackTrace);
  }
}

Future<void> _stopDartRuntime({
  required Server server,
  required ServerLifecycleContext lifecycleContext,
  required Set<WebSocket> activeSockets,
}) async {
  await _closeActiveDartWebSockets(activeSockets);

  if (server.onStop != null) {
    await server.onStop!(lifecycleContext);
  }
}

Future<void> _closeActiveDartWebSockets(Set<WebSocket> activeSockets) async {
  final sockets = List<WebSocket>.of(activeSockets);
  for (final socket in sockets) {
    final close = socket.close(WebSocketStatus.goingAway, 'Runtime shutdown');
    unawaited(close.catchError((Object _, StackTrace _) {}));
  }
}

Response _sanitizeErrorResponse(
  Response response, {
  required DartWebSocketRequest webSocket,
}) {
  if (response.status != HttpStatus.switchingProtocols) {
    return response;
  }

  if (webSocket.hasAcceptedUpgrade(response)) {
    return response;
  }

  return Response(
    'Internal Server Error',
    const ResponseInit(status: HttpStatus.internalServerError),
  );
}

void _validateDartServeParameters({
  required String host,
  required int port,
  required int backlog,
}) {
  if (host.trim().isEmpty) {
    throw RuntimeConfigurationError('Dart runtime host cannot be empty.');
  }

  if (port < 0 || port > 65535) {
    throw RuntimeConfigurationError(
      'Dart runtime port must be between 0 and 65535.',
    );
  }

  if (backlog < 0) {
    throw RuntimeConfigurationError('Dart runtime backlog cannot be negative.');
  }
}
