const defaultFetchEntryName = '__osrv_fetch__';

void defineFetchEntry(
  Object fetch, {
  String name = defaultFetchEntryName,
}) {
  fetch;
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
