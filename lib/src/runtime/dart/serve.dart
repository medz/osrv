import 'dart:async';
import 'dart:io';

import 'package:ht/ht.dart' show Response;

import '../../core/capabilities.dart';
import '../../core/errors.dart';
import '../../core/runtime.dart';
import '../../core/server.dart';
import 'config.dart';
import 'extension.dart';
import 'lifecycle_context.dart';
import 'request_bridge.dart';
import 'request_context.dart';
import 'response_bridge.dart';
import 'runtime.dart';

const dartRuntimeCapabilities = RuntimeCapabilities(
  streaming: true,
  websocket: false,
  fileSystem: true,
  backgroundTask: true,
  rawTcp: true,
  nodeCompat: false,
);

Future<Runtime> serveDartRuntime(
  Server server,
  DartRuntimeConfig config,
) async {
  _validateDartRuntimeConfig(config);

  final httpServer = await _bindDartHttpServer(config);

  final runtimeInfo = RuntimeInfo(
    name: 'dart',
    kind: 'server',
  );
  final lifecycleExtension = DartRuntimeExtension(server: httpServer);
  final lifecycleContext = DartServerLifecycleContext(
    runtime: runtimeInfo,
    capabilities: dartRuntimeCapabilities,
    extension: lifecycleExtension,
  );

  final pendingTasks = <Future<void>>{};
  final closedCompleter = Completer<void>();
  var stopHookTriggered = false;

  void trackTask(Future<void> task) {
    pendingTasks.add(task);
    task.whenComplete(() {
      pendingTasks.remove(task);
    });
  }

  Future<void> handleStop() async {
    if (stopHookTriggered) {
      return;
    }

    stopHookTriggered = true;
    try {
      if (server.onStop != null) {
        await server.onStop!(lifecycleContext);
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
    await httpServer.close(force: true);
    throw RuntimeStartupError(
      'Failed to start dart runtime.',
      error,
    );
  }

  unawaited(() async {
    try {
      await for (final request in httpServer) {
        final requestExtension = DartRuntimeExtension(
          server: httpServer,
          request: request,
          response: request.response,
        );
        final context = DartRequestContext(
          runtime: runtimeInfo,
          capabilities: dartRuntimeCapabilities,
          onWaitUntil: trackTask,
          extension: requestExtension,
        );

        try {
          final htRequest = await dartRequestFromHttpRequest(request);
          final response = await server.fetch(htRequest, context);
          await writeHtResponseToDartHttpResponse(response, request.response);
        } catch (error, stackTrace) {
          final handled = await _handleRequestError(
            server: server,
            error: error,
            stackTrace: stackTrace,
            context: lifecycleContext,
          );
          await writeHtResponseToDartHttpResponse(handled, request.response);
        }
      }
    } finally {
      await handleStop();
    }
  }());

  return DartRuntime(
    server: httpServer,
    info: runtimeInfo,
    capabilities: dartRuntimeCapabilities,
    closed: closedCompleter.future,
    host: config.host,
    port: httpServer.port,
    onClose: () {
      unawaited(handleStop());
    },
  );
}

Future<HttpServer> _bindDartHttpServer(
  DartRuntimeConfig config,
) async {
  try {
    return await HttpServer.bind(
      config.host,
      config.port,
      backlog: config.backlog,
      shared: config.shared,
      v6Only: config.v6Only,
    );
  } catch (error) {
    throw RuntimeStartupError(
      'Failed to bind dart runtime on ${config.host}:${config.port}.',
      error,
    );
  }
}

void _validateDartRuntimeConfig(DartRuntimeConfig config) {
  if (config.host.trim().isEmpty) {
    throw RuntimeConfigurationError(
      'DartRuntimeConfig.host cannot be empty.',
    );
  }

  if (config.port < 0 || config.port > 65535) {
    throw RuntimeConfigurationError(
      'DartRuntimeConfig.port must be between 0 and 65535.',
    );
  }

  if (config.backlog < 0) {
    throw RuntimeConfigurationError(
      'DartRuntimeConfig.backlog cannot be negative.',
    );
  }
}

Future<Response> _handleRequestError({
  required Server server,
  required Object error,
  required StackTrace stackTrace,
  required DartServerLifecycleContext context,
}) async {
  if (server.onError != null) {
    final response = await server.onError!(error, stackTrace, context);
    if (response != null) {
      return response;
    }
  }

  return Response.text(
    'Internal Server Error',
    status: HttpStatus.internalServerError,
  );
}
