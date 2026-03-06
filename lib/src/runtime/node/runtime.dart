import '../_internal/server/runtime_handle.dart';

final class NodeRuntime extends ServerRuntimeHandle {
  NodeRuntime({
    required super.info,
    required super.capabilities,
    required super.closed,
    required super.url,
    required super.onClose,
  });
}
