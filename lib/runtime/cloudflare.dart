import '../src/runtime/_internal/js/fetch_entry.dart' as entry;
import '../src/runtime/cloudflare/worker.dart' as worker;
import '../src/core/server.dart';

export '../src/runtime/cloudflare/extension.dart'
    show CloudflareRuntimeExtension;
export '../src/runtime/cloudflare/host.dart' show CloudflareExecutionContext;

/// Defines the JavaScript fetch export for the Cloudflare runtime entry.
void defineFetchExport(
  Server server, {
  String name = entry.defaultFetchEntryName,
}) {
  entry.defineFetchEntry(worker.createCloudflareFetchEntry(server), name: name);
}
