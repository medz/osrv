import '../_internal/server/contexts.dart';
import 'extension.dart';

final class BunServerLifecycleContext
    extends ServerLifecycleContextImpl<BunRuntimeExtension> {
  BunServerLifecycleContext({
    required super.runtime,
    required super.capabilities,
    required super.extension,
  });
}
