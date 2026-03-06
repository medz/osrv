import '../_internal/server/contexts.dart';
import 'extension.dart';

final class NodeRequestContext
    extends ServerRequestContextImpl<NodeRuntimeExtension> {
  NodeRequestContext({
    required super.runtime,
    required super.capabilities,
    required super.extension,
    required void Function(Future<void> task) onWaitUntil,
  }) : super(
         onWaitUntil: (extension, task) => onWaitUntil(task),
       );
}
