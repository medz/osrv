import '../_internal/server/contexts.dart';
import 'extension.dart';

final class DartServerLifecycleContext
    extends ServerLifecycleContextImpl<DartRuntimeExtension> {
  DartServerLifecycleContext({
    required super.runtime,
    required super.capabilities,
    required super.extension,
  });
}
