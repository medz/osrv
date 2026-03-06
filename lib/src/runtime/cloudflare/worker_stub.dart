import '../../core/server.dart';
import 'config.dart';

Object cloudflareWorker(
  Server server, [
  CloudflareRuntimeConfig config = const CloudflareRuntimeConfig(),
]) {
  server;
  config;
  throw UnsupportedError(
    'cloudflareWorker(...) requires a JavaScript host.',
  );
}
