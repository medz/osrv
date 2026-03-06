import '../_internal/js/entry_contexts.dart';
import 'extension.dart';
import 'host.dart';

final class CloudflareRequestContext
    extends JsEntryRequestContext<CloudflareRuntimeExtension<Object?, Object?>> {
  CloudflareRequestContext({
    required super.runtime,
    required super.capabilities,
    required super.extension,
  }) : super(
         onWaitUntil: (extension, task) {
           cloudflareWaitUntil(extension.context, task);
         },
       );
}
