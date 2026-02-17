import 'fetch_handler.dart';
import 'middleware.dart';
import 'plugin.dart';

enum HTTPProtocol { http, https }

class TLSOptions {
  const TLSOptions({required this.cert, required this.key, this.passphrase});

  final String cert;
  final String key;
  final String? passphrase;
}

class ServerOptions {
  const ServerOptions({
    required this.fetch,
    this.hostname,
    this.port,
    this.reusePort = false,
    this.silent = false,
    this.protocol,
    this.tls,
    this.http2,
    this.error,
    this.middleware = const [],
    this.plugins = const [],
    this.manual = false,
  });

  final String? hostname;
  final int? port;
  final bool reusePort;
  final bool silent;
  final HTTPProtocol? protocol;
  final TLSOptions? tls;
  final bool? http2;
  final FetchHandler fetch;
  final ErrorHandler? error;
  final Iterable<Middleware> middleware;
  final Iterable<Plugin> plugins;
  final bool manual;
}
