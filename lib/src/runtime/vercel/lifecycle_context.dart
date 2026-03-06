import '../_internal/js/entry_contexts.dart';
import 'extension.dart';

final class VercelServerLifecycleContext
    extends JsEntryServerLifecycleContext<VercelRuntimeExtension<Object?>> {
  VercelServerLifecycleContext({
    required super.runtime,
    required super.capabilities,
    required super.extension,
  });
}
