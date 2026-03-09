/// Configures the Bun runtime host selected by [serve].
final class BunRuntimeConfig {
  /// Creates a Bun runtime configuration.
  const BunRuntimeConfig({this.host = '127.0.0.1', this.port = 3000});

  /// Host interface Bun should bind to.
  final String host;

  /// TCP port Bun should bind to.
  final int port;
}
