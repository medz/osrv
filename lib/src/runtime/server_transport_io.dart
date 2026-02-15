import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ht/ht.dart' show Headers, Request, Response;

import '../exceptions.dart';
import '../request.dart';
import '../types.dart';
import 'server_transport.dart';

ServerTransport createServerTransport(ServerTransportHost host) {
  return _IoServerTransport(host);
}

final class _IoServerTransport implements ServerTransport {
  _IoServerTransport(this._host);

  final ServerTransportHost _host;

  HttpServer? _server;
  Future<void>? _readyFuture;
  Future<void>? _closeFuture;
  StreamSubscription<ProcessSignal>? _sigIntSub;
  StreamSubscription<ProcessSignal>? _sigTermSub;

  @override
  String get runtimeName => 'dart';

  @override
  ServerCapabilities get capabilities => const ServerCapabilities(
    http1: true,
    https: true,
    http2: false,
    websocket: true,
    requestStreaming: true,
    responseStreaming: true,
    waitUntil: true,
    edge: false,
    tls: true,
  );

  @override
  String? get url {
    final server = _server;
    if (server == null) {
      return null;
    }

    final protocol = server.port > 0
        ? (_host.resolvedProtocol == ServerProtocol.https ? 'https' : 'http')
        : 'http';

    final host = _urlHost(server.address.address);
    return '$protocol://$host:${server.port}';
  }

  @override
  Future<void> serve() {
    return _readyFuture ??= _bindAndServe();
  }

  @override
  Future<void> close({required bool force}) {
    return _closeFuture ??= _doClose(force: force);
  }

  Future<void> _bindAndServe() async {
    final useTls =
        _host.resolvedProtocol == ServerProtocol.https ||
        (_host.tlsOptions?.isConfigured ?? false);

    _server = useTls ? await _bindSecure() : await _bindHttp();
    _server!.autoCompress = false;
    _server!.idleTimeout = _host.securityLimits.requestTimeout;

    _server!.listen(
      (request) {
        unawaited(_handleRequest(request));
      },
      onError: (Object error, StackTrace stackTrace) {
        _host.logError('Transport stream error', error, stackTrace);
      },
      cancelOnError: false,
    );

    _installSignalHandlers();
    if (!_host.silent) {
      _host.logInfo('Listening on ${url ?? '(unknown url)'}');
    }
  }

  Future<HttpServer> _bindHttp() {
    return HttpServer.bind(
      _host.resolvedHostname,
      _host.resolvedPort,
      shared: _host.reusePort,
    );
  }

  Future<HttpServer> _bindSecure() {
    final tls = _host.tlsOptions;
    if (tls == null || !tls.isConfigured) {
      throw StateError(
        'TLS is required for https protocol but no cert/key set',
      );
    }

    final context = SecurityContext();
    _loadCertificate(context, tls.cert!);
    _loadPrivateKey(context, tls.key!, passphrase: tls.passphrase);

    return HttpServer.bindSecure(
      _host.resolvedHostname,
      _host.resolvedPort,
      context,
      shared: _host.reusePort,
    );
  }

  void _loadCertificate(SecurityContext context, String value) {
    if (_looksLikePem(value)) {
      context.useCertificateChainBytes(utf8.encode(value));
      return;
    }

    context.useCertificateChain(value);
  }

  void _loadPrivateKey(
    SecurityContext context,
    String value, {
    String? passphrase,
  }) {
    if (_looksLikePem(value)) {
      context.usePrivateKeyBytes(utf8.encode(value), password: passphrase);
      return;
    }

    context.usePrivateKey(value, password: passphrase);
  }

  bool _looksLikePem(String value) => value.contains('-----BEGIN ');

  Future<void> _handleRequest(HttpRequest ioRequest) async {
    final waitUntilTasks = <Future<Object?>>[];

    void waitUntil(Future<Object?> task) {
      waitUntilTasks.add(task);
      _host.trackBackgroundTask(task);
    }

    final request = _toFetchRequest(ioRequest);
    final isTls = _host.resolvedProtocol == ServerProtocol.https;
    final runtimeContext = RequestRuntimeContext(
      name: runtimeName,
      protocol: isTls ? 'https' : 'http',
      httpVersion: ioRequest.protocolVersion,
      tls: isTls,
      localAddress: _formatAddress(_server?.address.address, _server?.port),
      remoteAddress: _formatAddress(
        ioRequest.connectionInfo?.remoteAddress.address,
        ioRequest.connectionInfo?.remotePort,
      ),
      waitUntil: waitUntil,
      raw: RuntimeRawContext(
        dartRequest: ioRequest,
        dartResponse: ioRequest.response,
      ),
    );

    request.runtime = runtimeContext;
    request.context = <String, Object?>{};
    request.ip = _resolveClientIp(ioRequest);
    request.waitUntil = waitUntil;

    final response = await _host.dispatch(request);

    if (request.isWebSocketUpgraded) {
      await Future.wait(waitUntilTasks, eagerError: false);
      return;
    }

    await _writeResponse(ioRequest.response, response);
    await Future.wait(waitUntilTasks, eagerError: false);
  }

  ServerRequest _toFetchRequest(HttpRequest ioRequest) {
    final headers = Headers();
    ioRequest.headers.forEach((name, values) {
      for (final value in values) {
        headers.append(name, value);
      }
    });

    final uri = _absoluteRequestUri(ioRequest);
    final method = ioRequest.method;
    final hasBody = _methodAllowsBody(method);
    final body = hasBody
        ? _limitBody(
            ioRequest.cast<List<int>>(),
            _host.securityLimits.maxRequestBodyBytes,
          )
        : null;

    return ServerRequest(
      Request(uri, method: method, headers: headers, body: body),
    );
  }

  Stream<List<int>> _limitBody(Stream<List<int>> source, int maxBytes) async* {
    var total = 0;
    await for (final chunk in source) {
      total += chunk.length;
      if (total > maxBytes) {
        throw RequestLimitExceeded(maxBytes: maxBytes, actualBytes: total);
      }

      yield chunk;
    }
  }

  Uri _absoluteRequestUri(HttpRequest request) {
    if (request.requestedUri.hasScheme) {
      return request.requestedUri;
    }

    final protocol = _host.resolvedProtocol == ServerProtocol.https
        ? 'https'
        : 'http';
    final authority = request.headers.value(HttpHeaders.hostHeader);
    if (authority == null || authority.isEmpty) {
      final host = _server?.address.address ?? _host.resolvedHostname;
      final port = _server?.port ?? _host.resolvedPort;
      return Uri(
        scheme: protocol,
        host: host,
        port: port,
        path: request.uri.path,
        query: request.uri.hasQuery ? request.uri.query : null,
      );
    }

    final parsed = _parseAuthority(authority);
    return Uri(
      scheme: protocol,
      host: parsed.host,
      port: parsed.port,
      path: request.uri.path,
      query: request.uri.hasQuery ? request.uri.query : null,
    );
  }

  _Authority _parseAuthority(String authority) {
    final normalized = authority.trim();
    if (normalized.isEmpty) {
      return _Authority(_host.resolvedHostname, _host.resolvedPort);
    }

    if (normalized.startsWith('[')) {
      final close = normalized.indexOf(']');
      if (close > 0) {
        final host = normalized.substring(1, close);
        final rest = normalized.substring(close + 1);
        if (rest.startsWith(':')) {
          final port = int.tryParse(rest.substring(1));
          if (port != null) {
            return _Authority(host, port);
          }
        }

        return _Authority(host, _host.resolvedPort);
      }
    }

    final index = normalized.lastIndexOf(':');
    if (index > 0 && index < normalized.length - 1) {
      final maybePort = int.tryParse(normalized.substring(index + 1));
      if (maybePort != null) {
        return _Authority(normalized.substring(0, index), maybePort);
      }
    }

    return _Authority(normalized, _host.resolvedPort);
  }

  Future<void> _writeResponse(
    HttpResponse ioResponse,
    Response response,
  ) async {
    ioResponse.statusCode = response.status;
    ioResponse.reasonPhrase = response.statusText;

    for (final name in response.headers.names()) {
      final values = response.headers.getAll(name);
      if (values.isEmpty) {
        continue;
      }

      if (name == 'set-cookie') {
        for (final value in values) {
          ioResponse.headers.add(name, value);
        }
      } else {
        ioResponse.headers.set(name, values);
      }
    }

    final body = response.body;
    if (body != null) {
      await for (final chunk in body) {
        ioResponse.add(chunk);
      }
    }

    await ioResponse.close();
  }

  bool _methodAllowsBody(String method) {
    final normalized = method.toUpperCase();
    return normalized != 'GET' && normalized != 'HEAD' && normalized != 'TRACE';
  }

  String? _resolveClientIp(HttpRequest request) {
    if (_host.trustProxy) {
      final forwardedFor = request.headers.value('x-forwarded-for');
      if (forwardedFor != null && forwardedFor.isNotEmpty) {
        return forwardedFor.split(',').first.trim();
      }
    }

    return request.connectionInfo?.remoteAddress.address;
  }

  String? _formatAddress(String? host, int? port) {
    if (host == null || host.isEmpty) {
      return null;
    }

    if (port == null || port <= 0) {
      return host;
    }

    return '$host:$port';
  }

  String _urlHost(String host) {
    if (host == InternetAddress.anyIPv4.address ||
        host == InternetAddress.anyIPv6.address) {
      return _host.resolvedHostname;
    }

    return host;
  }

  void _installSignalHandlers() {
    if (!_host.gracefulShutdown.enabled) {
      return;
    }

    try {
      _sigIntSub = ProcessSignal.sigint.watch().listen((_) {
        unawaited(close(force: false));
      });
    } catch (_) {
      // Signal not supported on current platform.
    }

    try {
      _sigTermSub = ProcessSignal.sigterm.watch().listen((_) {
        unawaited(close(force: false));
      });
    } catch (_) {
      // Signal not supported on current platform.
    }
  }

  Future<void> _doClose({required bool force}) async {
    await _sigIntSub?.cancel();
    await _sigTermSub?.cancel();

    final server = _server;
    if (server == null) {
      return;
    }

    final closeFuture = server.close(force: force);
    if (force || !_host.gracefulShutdown.enabled) {
      await closeFuture;
      _server = null;
      return;
    }

    try {
      await closeFuture.timeout(_host.gracefulShutdown.gracefulTimeout);
    } on TimeoutException {
      _host.logWarn(
        'Graceful shutdown timeout reached. Forcing close in '
        '${_host.gracefulShutdown.forceTimeout.inSeconds}s.',
      );
      await server
          .close(force: true)
          .timeout(_host.gracefulShutdown.forceTimeout);
    } finally {
      _server = null;
    }
  }
}

final class _Authority {
  const _Authority(this.host, this.port);

  final String host;
  final int port;
}
