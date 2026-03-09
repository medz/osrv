/// Configures the Node runtime host selected by [serve].
final class NodeRuntimeConfig {
  /// Creates a Node runtime configuration.
  const NodeRuntimeConfig({this.host = '127.0.0.1', this.port = 3000});

  /// Host interface Node should bind to.
  final String host;

  /// TCP port Node should bind to.
  final int port;
}
