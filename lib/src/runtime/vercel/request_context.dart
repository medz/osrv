import '../_internal/js/entry_contexts.dart';
import 'extension.dart';

final class VercelRequestContext
    extends JsEntryRequestContext<VercelRuntimeExtension<Object?>> {
  VercelRequestContext({
    required super.runtime,
    required super.capabilities,
    required super.extension,
  }) : super(
         onWaitUntil: (extension, task) {
           extension.functions?.waitUntil(task);
         },
       );
}
