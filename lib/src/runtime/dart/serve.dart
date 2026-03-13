// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:io';

import 'package:ht/ht.dart' show Request;

import '../../core/capabilities.dart';
import '../../core/errors.dart';
import '../../core/request_context.dart';
import '../../core/runtime.dart';
import '../../core/server.dart';
import '../_internal/server/error_handler.dart';
import '../_internal/server/shutdown_coordinator.dart';
import 'extension.dart';
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
          final htRequest = Request(request);
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
    url: Uri(scheme: 'http', host: host, port: httpServer.port),
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
