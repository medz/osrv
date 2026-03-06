import '../../core/server.dart';

const defaultCloudflareFetchName = '__osrv_fetch__';

void defineCloudflareFetch(
  Server server, {
  String name = defaultCloudflareFetchName,
}) {
  server;
  if (name.trim().isEmpty) {
    throw ArgumentError.value(
      name,
      'name',
      'Cloudflare fetch export name must not be empty.',
    );
  }

  throw UnsupportedError(
    'defineCloudflareFetch(...) requires a JavaScript host.',
  );
}
