/// Describes which runtime-backed features are available to a server instance.
final class RuntimeCapabilities {
  /// Creates a capability snapshot for a concrete runtime.
  const RuntimeCapabilities({
    required this.streaming,
    required this.websocket,
    required this.fileSystem,
    required this.backgroundTask,
    required this.rawTcp,
    required this.nodeCompat,
  });

  /// Whether the runtime can stream response bodies.
  final bool streaming;

  /// Whether the runtime can upgrade requests to WebSocket connections.
  final bool websocket;

  /// Whether the runtime exposes a writable file system.
  final bool fileSystem;

  /// Whether the runtime can continue background work after a response starts.
  final bool backgroundTask;

  /// Whether the runtime can open raw TCP sockets.
  final bool rawTcp;

  /// Whether the runtime provides Node-compatible globals or APIs.
  final bool nodeCompat;
}
