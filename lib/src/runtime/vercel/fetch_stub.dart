import '../../core/server.dart';

const defaultVercelFetchName = '__osrv_fetch__';

void defineVercelFetch(
  Server server, {
  String name = defaultVercelFetchName,
}) {
  server;
  if (name.trim().isEmpty) {
    throw ArgumentError.value(
      name,
      'name',
      'Vercel fetch export name must not be empty.',
    );
  }
  throw UnsupportedError(
    'Vercel fetch exports require a JavaScript host.',
  );
}
