import 'dart:async';

import 'package:ht/ht.dart' show Response;

import '../../core/errors.dart';
import '../../core/runtime.dart';
import '../../core/server.dart';
import 'extension.dart';
import 'http_host.dart';
import 'lifecycle_context.dart';
import 'preflight.dart';
import 'request_bridge.dart';
import 'request_context.dart';
import 'response_bridge.dart';
import 'runtime.dart';

Future<Runtime> serveNodeRuntimeHost(
  Server server,
  NodeRuntimePreflight preflight,
) async {
  final httpModule = preflight.httpModule;
  if (httpModule == null) {
    throw preflight.toUnsupportedError();
  }

  final pendingTasks = <Future<void>>{};
  final pendingRequests = <Future<void>>{};
  final closedCompleter = Completer<void>();
  var stopHookTriggered = false;

  void trackTask(Future<void> task) {
    pendingTasks.add(task);
    task.whenComplete(() {
      pendingTasks.remove(task);
    });
  }

  void trackRequest(Future<void> request) {
    pendingRequests.add(request);
    request.whenComplete(() {
      pendingRequests.remove(request);
    });
  }

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
        onWaitUntil: trackTask,
      );
      trackRequest(operation);
      unawaited(operation);
    },
  );

  final binding = await listenNodeHttpServer(
    hostServer,
    host: preflight.config.host,
    port: preflight.config.port,
  );
  final runtimeInfo = const RuntimeInfo(
    name: 'node',
    kind: 'server',
  );
  runtimeUrl = Uri(
    scheme: 'http',
    host: binding.host,
    port: binding.port,
  );
  final lifecycleExtension = NodeRuntimeExtension(
    process: preflight.extension.process,
    server: hostServer,
  );
  final lifecycleContext = NodeServerLifecycleContext(
    runtime: runtimeInfo,
    capabilities: preflight.capabilities,
    extension: lifecycleExtension,
  );

  Future<void> handleStop() async {
    if (stopHookTriggered) {
      return;
    }

    stopHookTriggered = true;
    try {
      if (server.onStop != null) {
        await server.onStop!(lifecycleContext);
      }

      if (pendingRequests.isNotEmpty) {
        await Future.wait(pendingRequests);
      }

      if (pendingTasks.isNotEmpty) {
        await Future.wait(pendingTasks);
      }

      if (!closedCompleter.isCompleted) {
        closedCompleter.complete();
      }
    } catch (error, stackTrace) {
      if (!closedCompleter.isCompleted) {
        closedCompleter.completeError(error, stackTrace);
      }
    }
  }

  try {
    if (server.onStart != null) {
      await server.onStart!(lifecycleContext);
    }
  } catch (error) {
    await closeNodeHttpServer(hostServer);
    throw RuntimeStartupError(
      'Failed to start node runtime.',
      error,
    );
  }

  return NodeRuntime(
    info: runtimeInfo,
    capabilities: preflight.capabilities,
    closed: closedCompleter.future,
    url: runtimeUrl,
    onClose: () async {
      try {
        await closeNodeHttpServer(hostServer);
      } finally {
        await handleStop();
      }
      await closedCompleter.future;
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
  final context = NodeRequestContext(
    runtime: const RuntimeInfo(
      name: 'node',
      kind: 'server',
    ),
    capabilities: preflight.capabilities,
    onWaitUntil: onWaitUntil,
    extension: extension,
  );
  final lifecycleContext = NodeServerLifecycleContext(
    runtime: context.runtime,
    capabilities: context.capabilities,
    extension: NodeRuntimeExtension(
      process: preflight.extension.process,
      server: hostServer,
    ),
  );

  try {
    final htRequest = await nodeRequestFromHost(
      request,
      origin: origin,
    );
    final htResponse = await server.fetch(htRequest, context);
    await writeHtResponseToNodeServerResponse(htResponse, response);
  } catch (error, stackTrace) {
    final handled = await _handleRequestError(
      server: server,
      error: error,
      stackTrace: stackTrace,
      context: lifecycleContext,
    );
    await writeHtResponseToNodeServerResponse(handled, response);
  }
}

Future<Response> _handleRequestError({
  required Server server,
  required Object error,
  required StackTrace stackTrace,
  required NodeServerLifecycleContext context,
}) async {
  if (server.onError != null) {
    final response = await server.onError!(error, stackTrace, context);
    if (response != null) {
      return response;
    }
  }

  return Response.text(
    'Internal Server Error',
    status: 500,
  );
}
