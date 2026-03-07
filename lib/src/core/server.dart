import 'dart:async';

import 'package:ht/ht.dart' show Request, Response;

import 'request_context.dart';

export 'request_context.dart' show RequestContext, ServerLifecycleContext;

typedef ServerFetch =
    FutureOr<Response> Function(Request request, RequestContext context);

typedef ServerHook = FutureOr<void> Function(ServerLifecycleContext context);

typedef ServerErrorHook =
    FutureOr<Response?> Function(
      Object error,
      StackTrace stackTrace,
      ServerLifecycleContext context,
    );

final class Server {
  const Server({required this.fetch, this.onStart, this.onStop, this.onError});

  final ServerFetch fetch;
  final ServerHook? onStart;
  final ServerHook? onStop;
  final ServerErrorHook? onError;
}
