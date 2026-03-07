import '../core/server.dart';
import 'fetch_runtime.dart';

/// Default global export name used for generated fetch entrypoints.
const defaultFetchEntryName = '__osrv_fetch__';

/// Defines a JavaScript fetch entrypoint for the selected runtime family.
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

  throw UnsupportedError('Fetch entry exports require a JavaScript host.');
}
