import 'dart:async';

import 'capabilities.dart';
import 'extension.dart';
import 'runtime.dart';
import 'websocket.dart';

/// Carries runtime metadata shared by lifecycle hooks and request handling.
base class ServerLifecycleContext {
  /// Creates a lifecycle context for a concrete runtime invocation.
  ServerLifecycleContext({
    required this.runtime,
    required this.capabilities,
    RuntimeExtension? extension,
  }) : _extension = extension;

  /// Identifies the runtime that is invoking the server.
  final RuntimeInfo runtime;

  /// Declares which runtime capabilities are available for this invocation.
  final RuntimeCapabilities capabilities;
  final RuntimeExtension? _extension;

  /// Returns the runtime-specific extension when it matches [T].
  T? extension<T extends RuntimeExtension>() {
    final extension = _extension;
    if (extension is T) {
      return extension;
    }

    return null;
  }
}

/// Adds per-request controls on top of the shared lifecycle context.
base class RequestContext extends ServerLifecycleContext {
  /// Creates a request context for a single incoming request.
  RequestContext({
    required super.runtime,
    required super.capabilities,
    required void Function(Future<void> task) onWaitUntil,
    super.extension,
    WebSocketRequest? webSocket,
  }) : _onWaitUntil = onWaitUntil,
       _webSocket = webSocket;

  final void Function(Future<void> task) _onWaitUntil;
  final WebSocketRequest? _webSocket;

  /// Returns the request-scoped websocket upgrade capability when supported.
  WebSocketRequest? get webSocket => _webSocket;

  /// Registers a task that should outlive the immediate response.
  void waitUntil(Future<void> task) {
    _onWaitUntil(task);
  }
}
