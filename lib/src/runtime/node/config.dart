import '../../core/runtime_config.dart';

final class NodeRuntimeConfig implements RuntimeConfig {
  const NodeRuntimeConfig({this.host = '127.0.0.1', this.port = 3000});

  final String host;
  final int port;
}
