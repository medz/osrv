import 'dart:async';

import '../../core/errors.dart';
import '../../core/runtime.dart';
import '../../core/server.dart';
import '../_internal/server/error_handler.dart';
import '../_internal/server/runtime_handle.dart';
import '../_internal/server/shutdown_coordinator.dart';
import 'extension.dart';
import 'http_host.dart';
import 'preflight.dart';
import 'request_bridge.dart';
import 'response_bridge.dart';

Future<Runtime> serveNodeRuntimeHost(
  Server server,
  NodeRuntimePreflight preflight,
) async {
  final httpModule = preflight.httpModule;
  if (httpModule == null) {
    throw preflight.toUnsupportedError();
  }

  final coordinator = ShutdownCoordinator();

  late final NodeHttpServerHost hostServer;
  late final Uri runtimeUrl;
  hostServer = createNodeHttpServer(
    httpModule,
    onRequest: (request, response) {
      final operation = _handleNodeRequest(
        server: server,
        preflight: preflight,
        hostServer: hostServer,
        origin: runtimeUrl,
        request: request,
        response: response,
        onWaitUntil: coordinator.trackTask,
      );
      coordinator.trackRequest(operation);
      unawaited(operation);
    },
  );

  final binding = await listenNodeHttpServer(
    hostServer,
    host: preflight.config.host,
    port: preflight.config.port,
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
  } catch (error) {
    await closeNodeHttpServer(hostServer);
    throw RuntimeStartupError('Failed to start node runtime.', error);
  }

  return ServerRuntimeHandle(
    info: runtimeInfo,
    capabilities: preflight.capabilities,
    closed: coordinator.closed,
    url: runtimeUrl,
    onClose: () async {
      try {
        await closeNodeHttpServer(hostServer);
      } finally {
        await coordinator.stop(
          onStop: () async {
            if (server.onStop != null) {
              await server.onStop!(lifecycleContext);
            }
          },
        );
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
  final context = RequestContext(
    runtime: const RuntimeInfo(name: 'node', kind: 'server'),
    capabilities: preflight.capabilities,
    onWaitUntil: onWaitUntil,
    extension: extension,
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
    final htRequest = await nodeRequestFromHost(request, origin: origin);
    final htResponse = await server.fetch(htRequest, context);
    await writeHtResponseToNodeServerResponse(htResponse, response);
  } catch (error, stackTrace) {
    final handled = await handleServerError(
      server: server,
      error: error,
      stackTrace: stackTrace,
      context: lifecycleContext,
    );
    await writeHtResponseToNodeServerResponse(handled, response);
  }
}
