import 'dart:async';

import 'package:ht/ht.dart' show Request, Response;

import 'request_context.dart';

export 'request_context.dart' show RequestContext, ServerLifecycleContext;

/// Handles a single incoming request.
typedef ServerFetch =
    FutureOr<Response> Function(Request request, RequestContext context);

/// Runs during runtime startup and shutdown.
typedef ServerHook = FutureOr<void> Function(ServerLifecycleContext context);

/// Converts uncaught request errors into an optional response.
typedef ServerErrorHook =
    FutureOr<Response?> Function(
      Object error,
      StackTrace stackTrace,
      ServerLifecycleContext context,
    );

/// Declares the runtime-agnostic server contract consumed by `osrv`.
final class Server {
  /// Creates a server with a mandatory request handler and optional hooks.
  const Server({required this.fetch, this.onStart, this.onStop, this.onError});

  /// Handles each request routed into this server instance.
  final ServerFetch fetch;

  /// Runs once after the runtime has started successfully.
  final ServerHook? onStart;

  /// Runs once while the runtime is shutting down.
  final ServerHook? onStop;

  /// Optionally handles uncaught request exceptions.
  final ServerErrorHook? onError;
}
