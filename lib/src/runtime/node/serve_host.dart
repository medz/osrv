// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:crypto/crypto.dart';
import 'package:ht/ht.dart' show Response, ResponseInit;

import '../../core/errors.dart';
import '../../core/request_context.dart';
import '../../core/runtime.dart';
import '../../core/server.dart';
import '../../core/websocket.dart';
import '../_internal/server/error_handler.dart';
import '../_internal/server/runtime_handle.dart';
import '../_internal/server/shutdown_coordinator.dart';
import 'extension.dart';
import 'http_host.dart';
import 'preflight.dart';
import 'request_bridge.dart';
import 'response_bridge.dart';
import 'server_web_socket.dart';
import 'websocket_request.dart';

Future<Runtime> serveNodeRuntimeHost(
  Server server,
  NodeRuntimePreflight preflight,
) async {
  final httpModule = preflight.httpModule;
  if (httpModule == null) {
    throw preflight.toUnsupportedError();
  }

  final coordinator = ShutdownCoordinator();
  final startup = Completer<void>();
  unawaited(startup.future.catchError((Object _, StackTrace _) {}));
  final activeSockets = <NodeServerWebSocketAdapter>{};

  late final NodeHttpServerHost hostServer;
  late final Uri runtimeUrl;
  hostServer = createNodeHttpServer(
    httpModule,
    onRequest: (request, response) {
      final operation = () async {
        try {
          await startup.future;
        } catch (_) {
          await _writeNodeStartupFailureResponse(response);
          return;
        }

        await _handleNodeRequest(
          server: server,
          preflight: preflight,
          hostServer: hostServer,
          origin: runtimeUrl,
          request: request,
          response: response,
          onWaitUntil: coordinator.trackTask,
        );
      }();
      coordinator.trackRequest(operation);
      unawaited(operation);
    },
    onUpgrade: (request, socket, head) {
      final operation = () async {
        try {
          await startup.future;
        } catch (_) {
          await _writeNodeUpgradeFailureResponse(socket, status: 503);
          return;
        }

        await _handleNodeUpgrade(
          server: server,
          preflight: preflight,
          hostServer: hostServer,
          origin: runtimeUrl,
          request: request,
          socket: socket,
          head: head,
          coordinator: coordinator,
          activeSockets: activeSockets,
        );
      }();
      coordinator.trackRequest(operation);
      unawaited(operation);
    },
  );

  final binding = await listenNodeHttpServer(
    hostServer,
    host: preflight.host,
    port: preflight.port,
  );
  final runtimeInfo = const RuntimeInfo(name: 'node', kind: 'server');
  runtimeUrl = Uri(scheme: 'http', host: binding.host, port: binding.port);
  final lifecycleExtension = NodeRuntimeExtension(
    process: preflight.extension.process,
    server: hostServer,
  );
  final lifecycleContext = ServerLifecycleContext(
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
    await closeNodeHttpServer(hostServer);
    throw RuntimeStartupError('Failed to start node runtime.', error);
  }

  return ServerRuntimeHandle(
    info: runtimeInfo,
    capabilities: preflight.capabilities,
    closed: coordinator.closed,
    url: runtimeUrl,
    onClose: () async {
      final closeServer = closeNodeHttpServer(hostServer);
      try {
        await coordinator.stop(
          onStop: () async {
            await _closeActiveNodeWebSockets(activeSockets);
            if (server.onStop != null) {
              await server.onStop!(lifecycleContext);
            }
          },
        );
      } finally {
        await closeServer;
      }
      await coordinator.closed;
    },
  );
}

Future<void> _handleNodeRequest({
  required Server server,
  required NodeRuntimePreflight preflight,
  required NodeHttpServerHost hostServer,
  required Uri origin,
  required NodeIncomingMessageHost request,
  required NodeServerResponseHost response,
  required void Function(Future<void> task) onWaitUntil,
}) async {
  final extension = NodeRuntimeExtension(
    process: preflight.extension.process,
    server: hostServer,
    request: request,
    response: response,
  );
  final webSocket = NodeWebSocketRequest(
    isUpgradeRequest: false,
    requestedProtocols: const <String>[],
  );
  final context = RequestContext(
    runtime: const RuntimeInfo(name: 'node', kind: 'server'),
    capabilities: preflight.capabilities,
    onWaitUntil: onWaitUntil,
    extension: extension,
    webSocket: webSocket,
  );
  final lifecycleContext = ServerLifecycleContext(
    runtime: context.runtime,
    capabilities: context.capabilities,
    extension: NodeRuntimeExtension(
      process: preflight.extension.process,
      server: hostServer,
    ),
  );

  try {
    final htRequest = nodeRequestFromHost(request, origin: origin);
    final htResponse = await server.fetch(htRequest, context);
    if (htResponse.status == 101) {
      throw StateError(
        'Raw 101 responses are reserved for websocket upgrades. Use '
        'context.webSocket.accept(...) to accept an upgrade.',
      );
    }
    await writeHtResponseToNodeServerResponse(htResponse, response);
  } catch (error, stackTrace) {
    if (error is NodeTransportWriteError) {
      return;
    }

    final handled = await handleServerError(
      server: server,
      error: error,
      stackTrace: stackTrace,
      context: lifecycleContext,
    );

    try {
      await writeHtResponseToNodeServerResponse(
        _sanitizeNodeHttpErrorResponse(handled),
        response,
      );
    } on NodeTransportWriteError {
      return;
    }
  }
}

Future<void> _handleNodeUpgrade({
  required Server server,
  required NodeRuntimePreflight preflight,
  required NodeHttpServerHost hostServer,
  required Uri origin,
  required NodeIncomingMessageHost request,
  required NodeSocketHost socket,
  required JSAny? head,
  required ShutdownCoordinator coordinator,
  required Set<NodeServerWebSocketAdapter> activeSockets,
}) async {
  final snapshot = nodeRequestHeadFromHost(request);
  final webSocket = NodeWebSocketRequest(
    isUpgradeRequest: _isNodeUpgradeRequest(snapshot.rawHeaders),
    requestedProtocols: _requestedNodeProtocols(snapshot.rawHeaders),
  );
  final context = RequestContext(
    runtime: const RuntimeInfo(name: 'node', kind: 'server'),
    capabilities: preflight.capabilities,
    onWaitUntil: coordinator.trackTask,
    extension: NodeRuntimeExtension(
      process: preflight.extension.process,
      server: hostServer,
      request: request,
    ),
    webSocket: webSocket,
  );
  final lifecycleContext = ServerLifecycleContext(
    runtime: context.runtime,
    capabilities: context.capabilities,
    extension: NodeRuntimeExtension(
      process: preflight.extension.process,
      server: hostServer,
    ),
  );

  try {
    final htRequest = nodeRequestFromHeadSnapshot(snapshot, origin: origin);
    final response = await server.fetch(htRequest, context);
    final accepted = webSocket.takeAcceptedUpgrade(response);
    if (accepted == null) {
      await _writeNodeUpgradeHttpResponse(socket, response);
      return;
    }

    if (!_canCommitNodeWebSocketUpgrade(snapshot)) {
      await _writeNodeUpgradeFailureResponse(socket, status: 400);
      return;
    }

    final key = _headerValue(snapshot.rawHeaders, 'sec-websocket-key');
    if (key == null || key.isEmpty) {
      await _writeNodeUpgradeFailureResponse(socket, status: 400);
      return;
    }

    final protocol = accepted.protocol;
    await _writeNodeWebSocketHandshake(socket, key: key, protocol: protocol);

    final adapter = NodeServerWebSocketAdapter(
      socket: socket,
      incoming: nodeSocketReadable(socket, head: head),
      protocol: protocol ?? '',
    );
    activeSockets.add(adapter);
    final session = _runNodeWebSocketSession(adapter, accepted.handler);
    coordinator.trackConnection(
      adapter.closed.whenComplete(() {
        activeSockets.remove(adapter);
      }),
    );
    coordinator.trackTask(session);
    unawaited(session);
  } catch (error, stackTrace) {
    final handled = await handleServerError(
      server: server,
      error: error,
      stackTrace: stackTrace,
      context: lifecycleContext,
    );
    await _writeNodeUpgradeHttpResponse(
      socket,
      _sanitizeNodeUpgradeErrorResponse(handled, webSocket: webSocket),
    );
  }
}

Future<void> _runNodeWebSocketSession(
  NodeServerWebSocketAdapter socket,
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

Future<void> _writeNodeStartupFailureResponse(
  NodeServerResponseHost response,
) async {
  try {
    nodeServerResponseSetStatus(
      response,
      status: 503,
      statusText: 'Service Unavailable',
    );
    await nodeServerResponseEnd(response, 'Service Unavailable');
  } catch (_) {
    // The listener may already be closing after startup failure.
  }
}

Future<void> _writeNodeUpgradeFailureResponse(
  NodeSocketHost socket, {
  required int status,
}) async {
  final message = switch (status) {
    400 => 'Bad Request',
    503 => 'Service Unavailable',
    _ => 'HTTP Error',
  };
  await _writeNodeUpgradeHttpResponse(
    socket,
    Response(message, ResponseInit(status: status, statusText: message)),
  );
}

Future<void> _writeNodeUpgradeHttpResponse(
  NodeSocketHost socket,
  Response response,
) async {
  final body = await response.bytes();
  final statusText = response.statusText.isEmpty
      ? 'HTTP Response'
      : response.statusText;
  final builder = StringBuffer()
    ..write('HTTP/1.1 ${response.status} $statusText\r\n');

  var hasContentLength = false;
  for (final MapEntry(:key, :value) in response.headers.entries()) {
    if (key.toLowerCase() == 'content-length') {
      hasContentLength = true;
    }
    builder.write('$key: $value\r\n');
  }
  if (!hasContentLength) {
    builder.write('content-length: ${body.length}\r\n');
  }
  builder.write('\r\n');

  await nodeSocketWrite(socket, builder.toString());
  if (body.isNotEmpty) {
    await nodeSocketWrite(socket, body);
  }
  await nodeSocketEnd(socket);
}

Future<void> _writeNodeWebSocketHandshake(
  NodeSocketHost socket, {
  required String key,
  required String? protocol,
}) async {
  final accept = base64.encode(
    sha1.convert(utf8.encode('$key$_nodeWebSocketGuid')).bytes,
  );
  final buffer = StringBuffer()
    ..write('HTTP/1.1 101 Switching Protocols\r\n')
    ..write('Upgrade: websocket\r\n')
    ..write('Connection: Upgrade\r\n')
    ..write('Sec-WebSocket-Accept: $accept\r\n');
  if (protocol != null && protocol.isNotEmpty) {
    buffer.write('Sec-WebSocket-Protocol: $protocol\r\n');
  }
  buffer.write('\r\n');
  await nodeSocketWrite(socket, buffer.toString());
}

Future<void> _closeActiveNodeWebSockets(
  Set<NodeServerWebSocketAdapter> activeSockets,
) async {
  final sockets = List<NodeServerWebSocketAdapter>.of(activeSockets);
  for (final socket in sockets) {
    try {
      await socket.close(1001, 'Runtime shutdown');
    } catch (_) {}
  }
}

Response _sanitizeNodeUpgradeErrorResponse(
  Response response, {
  required NodeWebSocketRequest webSocket,
}) {
  if (response.status != 101 || webSocket.hasAcceptedUpgrade(response)) {
    return response;
  }

  return Response('Internal Server Error', const ResponseInit(status: 500));
}

Response _sanitizeNodeHttpErrorResponse(Response response) {
  if (response.status != 101) {
    return response;
  }

  return Response('Internal Server Error', const ResponseInit(status: 500));
}

bool _canCommitNodeWebSocketUpgrade(NodeRequestHeadSnapshot snapshot) {
  final method = snapshot.method;
  if (method == null || method.toUpperCase() != 'GET') {
    return false;
  }

  final version = _headerValue(snapshot.rawHeaders, 'sec-websocket-version');
  return version == '13';
}

bool _isNodeUpgradeRequest(Object? rawHeaders) {
  final upgrade = _headerValue(rawHeaders, 'upgrade');
  final connection = _headerValue(rawHeaders, 'connection');
  return upgrade?.toLowerCase() == 'websocket' &&
      connection?.toLowerCase().contains('upgrade') == true;
}

List<String> _requestedNodeProtocols(Object? rawHeaders) {
  final header = _headerValue(rawHeaders, 'sec-websocket-protocol');
  if (header == null || header.isEmpty) {
    return const <String>[];
  }

  return header
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

String? _headerValue(Object? rawHeaders, String name) {
  if (rawHeaders is! Map) {
    return null;
  }

  for (final entry in rawHeaders.entries) {
    if (entry.key?.toString().toLowerCase() != name) {
      continue;
    }

    final value = entry.value;
    return switch (value) {
      String() => value,
      List<Object?>() when value.isNotEmpty => value.first?.toString(),
      _ => value?.toString(),
    };
  }

  return null;
}

const _nodeWebSocketGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
