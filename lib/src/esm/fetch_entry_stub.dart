void defineFetchExport(Object fetch, {String name = '__osrv_fetch__'}) {
  fetch;
  if (name.trim().isEmpty) {
    throw ArgumentError.value(
      name,
      'name',
      'Fetch entry export name must not be empty.',
    );
  }

  throw UnsupportedError('Fetch entry exports require a JavaScript host.');
}
