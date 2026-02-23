import 'handlers.dart';
import 'plugin.dart';

enum HTTPProtocol { http, https }

final class TLSOptions {
  const TLSOptions({required this.cert, required this.key, this.passphrase});

  final String cert;
  final String key;
  final String? passphrase;
}

final class ServerOptions {
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
    this.middleware = const <Middleware>[],
    this.plugins = const <ServerPlugin>[],
    this.manual = false,
    this.env,
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
  final Iterable<ServerPlugin> plugins;
  final bool manual;
  final Map<String, String>? env;

  ServerOptions copyWith({
    String? hostname,
    int? port,
    bool? reusePort,
    bool? silent,
    HTTPProtocol? protocol,
    TLSOptions? tls,
    bool? http2,
    FetchHandler? fetch,
    ErrorHandler? error,
    Iterable<Middleware>? middleware,
    Iterable<ServerPlugin>? plugins,
    bool? manual,
    Map<String, String>? env,
  }) {
    return ServerOptions(
      hostname: hostname ?? this.hostname,
      port: port ?? this.port,
      reusePort: reusePort ?? this.reusePort,
      silent: silent ?? this.silent,
      protocol: protocol ?? this.protocol,
      tls: tls ?? this.tls,
      http2: http2 ?? this.http2,
      fetch: fetch ?? this.fetch,
      error: error ?? this.error,
      middleware: middleware ?? this.middleware,
      plugins: plugins ?? this.plugins,
      manual: manual ?? this.manual,
      env: env ?? this.env,
    );
  }
}
