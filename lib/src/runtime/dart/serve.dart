// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:io';

import '../../core/capabilities.dart';
import '../../core/errors.dart';
import '../../core/runtime.dart';
import '../../core/server.dart';
import '../_internal/server/error_handler.dart';
import '../_internal/server/shutdown_coordinator.dart';
import 'config.dart';
import 'extension.dart';
import 'request_bridge.dart';
import 'response_bridge.dart';
import '../_internal/server/runtime_handle.dart';

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

  final runtimeInfo = RuntimeInfo(name: 'dart', kind: 'server');
  final lifecycleExtension = DartRuntimeExtension(server: httpServer);
  final lifecycleContext = ServerLifecycleContext(
    runtime: runtimeInfo,
    capabilities: dartRuntimeCapabilities,
    extension: lifecycleExtension,
  );

  final coordinator = ShutdownCoordinator();

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
        final requestExtension = DartRuntimeExtension(
          server: httpServer,
          request: request,
          response: request.response,
        );
        final context = RequestContext(
          runtime: runtimeInfo,
          capabilities: dartRuntimeCapabilities,
          onWaitUntil: coordinator.trackTask,
          extension: requestExtension,
        );

        try {
          final htRequest = await dartRequestFromHttpRequest(request);
          final response = await server.fetch(htRequest, context);
          await writeHtResponseToDartHttpResponse(response, request.response);
        } catch (error, stackTrace) {
          final handled = await handleServerError(
            server: server,
            error: error,
            stackTrace: stackTrace,
            context: lifecycleContext,
            defaultStatus: HttpStatus.internalServerError,
          );
          await writeHtResponseToDartHttpResponse(handled, request.response);
        }
      }
    } finally {
      await coordinator.stop(
        onStop: () async {
          if (server.onStop != null) {
            await server.onStop!(lifecycleContext);
          }
        },
        waitForRequests: false,
      );
    }
  }());

  return ServerRuntimeHandle(
    info: runtimeInfo,
    capabilities: dartRuntimeCapabilities,
    closed: coordinator.closed,
    url: Uri(scheme: 'http', host: config.host, port: httpServer.port),
    onClose: () async {
      unawaited(
        coordinator.stop(
          onStop: () async {
            if (server.onStop != null) {
              await server.onStop!(lifecycleContext);
            }
          },
          waitForRequests: false,
        ),
      );
      await httpServer.close();
      await coordinator.closed;
    },
  );
}

Future<HttpServer> _bindDartHttpServer(DartRuntimeConfig config) async {
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
    throw RuntimeConfigurationError('DartRuntimeConfig.host cannot be empty.');
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
