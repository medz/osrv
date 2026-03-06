import '../_internal/js/entry_contexts.dart';
import 'extension.dart';

final class CloudflareServerLifecycleContext
    extends JsEntryServerLifecycleContext<
        CloudflareRuntimeExtension<Object?, Object?>> {
  CloudflareServerLifecycleContext({
    required super.runtime,
    required super.capabilities,
    required super.extension,
  });
}
