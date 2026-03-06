@JS()
library;

import 'dart:async';
import 'dart:js_interop';

import '../../core/capabilities.dart';
import 'package:ht/ht.dart' show Response;
import 'package:web/web.dart' as web;

import '../../core/errors.dart';
import '../../core/runtime.dart';
import '../../core/server.dart';
import 'extension.dart';
import 'interop.dart';
import 'lifecycle_context.dart';
import 'preflight.dart';
import 'request_bridge.dart';
import 'request_context.dart';
import 'request_host.dart';
import 'response_bridge.dart';
import 'runtime.dart';

Future<Runtime> serveBunRuntimeHost(
  Server server,
  BunRuntimePreflight preflight,
) async {
  final bun = preflight.extension.bun;
  if (bun == null) {
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

  final runtimeInfo = const RuntimeInfo(
    name: 'bun',
    kind: 'server',
  );
  late final BunServerHost hostServer;
  late final BunRuntimeExtension lifecycleExtension;
  late final BunServerLifecycleContext lifecycleContext;

  JSPromise<web.Response> fetch(
    web.Request request, [
    JSAny? serverHost,
  ]) {
    serverHost;
    final requestHost = bunRequestHostFromWebRequest(request);
    final operation = _handleBunRequest(
      server: server,
      runtimeInfo: runtimeInfo,
      capabilities: preflight.capabilities,
      bun: bun,
      hostServer: hostServer,
      request: request,
      requestHost: requestHost,
      onWaitUntil: trackTask,
      lifecycleContext: lifecycleContext,
    );
    trackRequest(operation);
    return operation.toJS;
  }

  try {
    hostServer = bunServe(
      bun,
      host: preflight.config.host,
      port: preflight.config.port,
      fetch: fetch.toJS,
    );
  } catch (error) {
    throw RuntimeStartupError(
      'Failed to bind bun runtime on ${preflight.config.host}:${preflight.config.port}.',
      error,
    );
  }

  lifecycleExtension = BunRuntimeExtension(
    bun: bun,
    server: hostServer,
  );
  lifecycleContext = BunServerLifecycleContext(
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
    await stopBunServer(hostServer, force: true);
    throw RuntimeStartupError(
      'Failed to start bun runtime.',
      error,
    );
  }

  final runtimeUrl = Uri(
    scheme: 'http',
    host: preflight.config.host,
    port: bunServerPort(hostServer) ?? preflight.config.port,
  );

  return BunRuntime(
    info: runtimeInfo,
    capabilities: preflight.capabilities,
    closed: closedCompleter.future,
    url: runtimeUrl,
    onClose: () async {
      try {
        await stopBunServer(hostServer);
      } finally {
        await handleStop();
      }
      await closedCompleter.future;
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
  required BunServerLifecycleContext lifecycleContext,
}) async {
  final extension = BunRuntimeExtension(
    bun: bun,
    server: hostServer,
    request: requestHost,
  );
  final context = BunRequestContext(
    runtime: runtimeInfo,
    capabilities: capabilities,
    onWaitUntil: onWaitUntil,
    extension: extension,
  );

  try {
    final htRequest = bunRequestToHtRequest(request);
    final htResponse = await server.fetch(htRequest, context);
    return bunResponseFromHtResponse(htResponse);
  } catch (error, stackTrace) {
    final handled = await _handleRequestError(
      server: server,
      error: error,
      stackTrace: stackTrace,
      context: lifecycleContext,
    );
    return bunResponseFromHtResponse(handled);
  }
}

Future<Response> _handleRequestError({
  required Server server,
  required Object error,
  required StackTrace stackTrace,
  required BunServerLifecycleContext context,
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
