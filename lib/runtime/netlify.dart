import '../src/runtime/_internal/js/fetch_entry.dart' as entry;
import '../src/runtime/netlify/fetch.dart' as fetch_runtime;
import '../src/core/server.dart';

export '../src/runtime/netlify/extension.dart' show NetlifyRuntimeExtension;
export '../src/runtime/netlify/host.dart' show NetlifyContext;

/// Defines the JavaScript fetch export for the Netlify runtime entry.
void defineFetchExport(
  Server server, {
  String name = entry.defaultFetchEntryName,
}) {
  entry.defineFetchEntry(
    fetch_runtime.createNetlifyFetchEntry(server),
    name: name,
  );
}
