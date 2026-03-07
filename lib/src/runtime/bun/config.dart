import '../../core/runtime_config.dart';

final class BunRuntimeConfig implements RuntimeConfig {
  const BunRuntimeConfig({this.host = '127.0.0.1', this.port = 3000});

  final String host;
  final int port;
}
