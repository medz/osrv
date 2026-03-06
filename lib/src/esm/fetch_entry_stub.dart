import '../core/server.dart';
import 'fetch_runtime.dart';

const defaultFetchEntryName = '__osrv_fetch__';

void defineFetchEntry(
  Server server, {
  required FetchEntryRuntime runtime,
  String name = defaultFetchEntryName,
}) {
  server;
  runtime;
  if (name.trim().isEmpty) {
    throw ArgumentError.value(
      name,
      'name',
      'Fetch entry export name must not be empty.',
    );
  }

  throw UnsupportedError(
    'Fetch entry exports require a JavaScript host.',
  );
}
