import '../_internal/server/contexts.dart';
import 'extension.dart';

final class NodeServerLifecycleContext
    extends ServerLifecycleContextImpl<NodeRuntimeExtension> {
  NodeServerLifecycleContext({
    required super.runtime,
    required super.capabilities,
    required super.extension,
  });
}
