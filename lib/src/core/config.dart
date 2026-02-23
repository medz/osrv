import '../runtime/environment.dart';
import '../types/index.dart';

final class ServerConfig {
  const ServerConfig._({
    required this.hostname,
    required this.port,
    required this.reusePort,
    required this.silent,
    required this.protocol,
    required this.tls,
    required this.http2,
    required this.manual,
    required this.environment,
    required this.middleware,
    required this.plugins,
  });

  factory ServerConfig.resolve(ServerOptions options) {
    final environment = options.env ?? readRuntimeEnvironment();
    final tls = _resolveTls(options.tls, environment);
    final protocol =
        options.protocol ??
        (tls != null || _hasTlsEnvironmentInputs(environment)
            ? HTTPProtocol.https
            : HTTPProtocol.http);

    return ServerConfig._(
      hostname: _resolveHostname(options.hostname, environment),
      port: _resolvePort(options.port, environment),
      reusePort: options.reusePort,
      silent: options.silent,
      protocol: protocol,
      tls: tls,
      http2: _resolveHttp2(options.http2, environment),
      manual: options.manual,
      environment: Map<String, String>.unmodifiable(environment),
      middleware: List<Middleware>.unmodifiable(options.middleware),
      plugins: List<ServerPlugin>.unmodifiable(options.plugins),
    );
  }

  final String hostname;
  final int port;
  final bool reusePort;
  final bool silent;
  final HTTPProtocol protocol;
  final TLSOptions? tls;
  final bool http2;
  final bool manual;
  final Map<String, String> environment;
  final List<Middleware> middleware;
  final List<ServerPlugin> plugins;

  bool get secure => protocol == HTTPProtocol.https || tls != null;

  Uri defaultUrl() {
    return Uri(scheme: secure ? 'https' : 'http', host: hostname, port: port);
  }

  static String _resolveHostname(
    String? hostname,
    Map<String, String> environment,
  ) {
    return _firstNonEmpty(
          hostname,
          environment['HOST'],
          environment['HOSTNAME'],
        ) ??
        '127.0.0.1';
  }

  static int _resolvePort(int? port, Map<String, String> environment) {
    if (port case final explicit?) {
      return explicit;
    }

    final fromEnv = _parseInt(environment['PORT']);
    if (fromEnv case final envPort?) {
      return envPort;
    }

    return 3000;
  }

  static bool _resolveHttp2(bool? http2, Map<String, String> environment) {
    if (http2 case final explicit?) {
      return explicit;
    }

    return _parseBoolish(environment['HTTP2']) ?? false;
  }

  static TLSOptions? _resolveTls(
    TLSOptions? explicit,
    Map<String, String> environment,
  ) {
    if (explicit case final tls?) {
      return tls;
    }

    final cert = _firstNonEmpty(
      environment['TLS_CERT'],
      environment['SSL_CERT'],
      environment['HTTPS_CERT'],
    );
    final key = _firstNonEmpty(
      environment['TLS_KEY'],
      environment['SSL_KEY'],
      environment['HTTPS_KEY'],
    );
    if (cert == null || key == null) {
      return null;
    }

    return TLSOptions(
      cert: cert,
      key: key,
      passphrase: _firstNonEmpty(
        environment['TLS_PASSPHRASE'],
        environment['SSL_PASSPHRASE'],
        environment['HTTPS_PASSPHRASE'],
      ),
    );
  }

  static bool _hasTlsEnvironmentInputs(Map<String, String> environment) {
    return _firstNonEmpty(
              environment['TLS_CERT'],
              environment['SSL_CERT'],
              environment['HTTPS_CERT'],
            ) !=
            null &&
        _firstNonEmpty(
              environment['TLS_KEY'],
              environment['SSL_KEY'],
              environment['HTTPS_KEY'],
            ) !=
            null;
  }

  static String? _firstNonEmpty(
    String? first, [
    String? second,
    String? third,
  ]) {
    for (final value in <String?>[first, second, third]) {
      final normalized = value?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }

  static int? _parseInt(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return int.tryParse(normalized);
  }

  static bool? _parseBoolish(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    switch (normalized) {
      case '1':
      case 'true':
      case 'yes':
      case 'on':
        return true;
      case '0':
      case 'false':
      case 'no':
      case 'off':
        return false;
      default:
        return null;
    }
  }
}
