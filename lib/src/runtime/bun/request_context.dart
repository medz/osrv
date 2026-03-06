import '../_internal/server/contexts.dart';
import 'extension.dart';

final class BunRequestContext
    extends ServerRequestContextImpl<BunRuntimeExtension> {
  BunRequestContext({
    required super.runtime,
    required super.capabilities,
    required super.extension,
    required void Function(Future<void> task) onWaitUntil,
  }) : super(
         onWaitUntil: (extension, task) => onWaitUntil(task),
       );
}
