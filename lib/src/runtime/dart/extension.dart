import 'dart:io';

import '../../core/extension.dart';

/// Exposes `dart:io` server objects through [RequestContext.extension].
final class DartRuntimeExtension implements RuntimeExtension {
  /// Creates a Dart runtime extension snapshot.
  const DartRuntimeExtension({
    required this.server,
    this.request,
    this.response,
  });

  /// The listening HTTP server for the active runtime.
  final HttpServer server;

  /// The active `dart:io` request, when handling a request.
  final HttpRequest? request;

  /// The active `dart:io` response writer, when handling a request.
  final HttpResponse? response;
}
