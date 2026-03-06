import '../core/server.dart';
import '../runtime/_internal/js/fetch_entry.dart' as internal;
import '../runtime/cloudflare/worker_js.dart' as cloudflare;
import '../runtime/vercel/fetch_js.dart' as vercel;
import 'fetch_runtime.dart';

const defaultFetchEntryName = internal.defaultFetchEntryName;

void defineFetchEntry(
  Server server, {
  required FetchEntryRuntime runtime,
  String name = defaultFetchEntryName,
}) {
  final fetch = switch (runtime) {
    FetchEntryRuntime.cloudflare => cloudflare.createCloudflareFetchEntry(
      server,
    ),
    FetchEntryRuntime.vercel => vercel.createVercelFetchEntry(server),
  };

  internal.defineFetchEntry(fetch, name: name);
}
