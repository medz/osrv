/// Configures the native Dart `dart:io` runtime selected by [serve].
final class DartRuntimeConfig {
  /// Creates a Dart runtime configuration.
  const DartRuntimeConfig({
    this.host = '127.0.0.1',
    this.port = 3000,
    this.backlog = 0,
    this.shared = false,
    this.v6Only = false,
  }) : assert(port >= 0 && port <= 65535, 'port must be between 0 and 65535'),
       assert(backlog >= 0, 'backlog cannot be negative');

  /// Host interface the HTTP server should bind to.
  final String host;

  /// TCP port the HTTP server should bind to.
  final int port;

  /// Maximum number of pending connections held by the OS.
  final int backlog;

  /// Whether the listening socket may be shared across isolates.
  final bool shared;

  /// Whether IPv6 sockets should reject IPv4-mapped connections.
  final bool v6Only;
}
