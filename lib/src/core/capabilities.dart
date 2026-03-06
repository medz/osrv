final class RuntimeCapabilities {
  const RuntimeCapabilities({
    required this.streaming,
    required this.websocket,
    required this.fileSystem,
    required this.backgroundTask,
    required this.rawTcp,
    required this.nodeCompat,
  });

  final bool streaming;
  final bool websocket;
  final bool fileSystem;
  final bool backgroundTask;
  final bool rawTcp;
  final bool nodeCompat;
}
