// ignore_for_file: public_member_api_docs

@JS()
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:ht/ht.dart' show Request;
import 'package:web/web.dart' as web;

import '../../core/capabilities.dart';
import '../../core/errors.dart';
import '../../core/request_context.dart';
import '../../core/runtime.dart';
import '../../core/server.dart';
import '../_internal/js/web_response_bridge.dart';
import '../_internal/server/error_handler.dart';
import '../_internal/server/runtime_handle.dart';
import '../_internal/server/shutdown_coordinator.dart';
import 'extension.dart';
import 'interop.dart';
import 'preflight.dart';
import 'request_host.dart';

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
}) async {
  final requestHost = denoRequestHostFromWebRequest(request);
  final extension = DenoRuntimeExtension(
    deno: deno,
    server: hostServer,
    request: requestHost,
  );
  final context = RequestContext(
    runtime: runtimeInfo,
    capabilities: capabilities,
    onWaitUntil: onWaitUntil,
    extension: extension,
  );

  try {
    final htRequest = Request(request);
    final htResponse = await server.fetch(htRequest, context);
    return webResponseFromHtResponse(htResponse);
  } catch (error, stackTrace) {
    final handled = await handleServerError(
      server: server,
      error: error,
      stackTrace: stackTrace,
      context: lifecycleContext,
    );
    return webResponseFromHtResponse(handled);
  }
}

web.Response _denoStartupFailureResponse() {
  return web.Response(
    'Service Unavailable'.toJS,
    web.ResponseInit(status: 503, statusText: 'Service Unavailable'),
  );
}
