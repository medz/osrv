import '../src/runtime/_internal/js/fetch_entry.dart' as entry;
import '../src/runtime/vercel/fetch.dart' as fetch_runtime;
import '../src/core/server.dart';

export '../src/runtime/vercel/extension.dart' show VercelRuntimeExtension;
export '../src/runtime/vercel/functions.dart'
    show VercelFunctions, VercelRuntimeCache;

/// Defines the JavaScript fetch export for the Vercel runtime entry.
void defineFetchExport(
  Server server, {
  String name = entry.defaultFetchEntryName,
}) {
  entry.defineFetchEntry(
    fetch_runtime.createVercelFetchEntry(server),
    name: name,
  );
}
