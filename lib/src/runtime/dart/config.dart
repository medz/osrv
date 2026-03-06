import '../../core/runtime_config.dart';

final class DartRuntimeConfig implements RuntimeConfig {
  const DartRuntimeConfig({
    this.host = '127.0.0.1',
    this.port = 3000,
    this.backlog = 0,
    this.shared = false,
    this.v6Only = false,
  });

  final String host;
  final int port;
  final int backlog;
  final bool shared;
  final bool v6Only;
}
