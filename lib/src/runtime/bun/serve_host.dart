// ignore_for_file: public_member_api_docs

@JS()
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:ht/ht.dart' show Request;
import '../../core/capabilities.dart';
import 'package:web/web.dart' as web;

import '../../core/errors.dart';
import '../../core/request_context.dart';
import '../../core/runtime.dart';
import '../../core/server.dart';
import '../_internal/server/error_handler.dart';
import '../_internal/server/runtime_handle.dart';
import '../_internal/server/shutdown_coordinator.dart';
import '../_internal/js/web_response_bridge.dart';
import 'extension.dart';
import 'interop.dart';
import 'preflight.dart';
import 'request_host.dart';

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
  unawaited(startup.future.catchError((Object _, StackTrace stackTrace) {}));

  final runtimeInfo = const RuntimeInfo(name: 'bun', kind: 'server');
  late final BunServerHost hostServer;
  late final BunRuntimeExtension lifecycleExtension;
  late final ServerLifecycleContext lifecycleContext;

  JSPromise<web.Response> fetch(web.Request request, [JSAny? serverHost]) {
    serverHost;
    final requestHost = bunRequestHostFromWebRequest(request);
    final operation = () async {
      await startup.future;
      return _handleBunRequest(
        server: server,
        runtimeInfo: runtimeInfo,
        capabilities: preflight.capabilities,
        bun: bun,
        hostServer: hostServer,
        request: request,
        requestHost: requestHost,
        onWaitUntil: coordinator.trackTask,
        lifecycleContext: lifecycleContext,
      );
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
      try {
        await stopBunServer(hostServer);
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

Future<web.Response> _handleBunRequest({
  required Server server,
  required RuntimeInfo runtimeInfo,
  required RuntimeCapabilities capabilities,
  required BunGlobal? bun,
  required BunServerHost? hostServer,
  required web.Request request,
  required BunRequestHost? requestHost,
  required void Function(Future<void> task) onWaitUntil,
  required ServerLifecycleContext lifecycleContext,
}) async {
  final extension = BunRuntimeExtension(
    bun: bun,
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
