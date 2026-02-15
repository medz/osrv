import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ht/ht.dart' show Headers, Request, Response;
import 'package:http2/http2.dart' as h2;
import 'package:http2/multiprotocol_server.dart';

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
  MultiProtocolHttpServer? _multiProtocolServer;
  Future<void>? _readyFuture;
  Future<void>? _closeFuture;
  StreamSubscription<ProcessSignal>? _sigIntSub;
  StreamSubscription<ProcessSignal>? _sigTermSub;
  bool _http2Enabled = false;
  InternetAddress? _boundAddress;
  int? _boundPort;
  bool _isSecureBound = false;

  @override
  String get runtimeName => 'dart';

  @override
  ServerCapabilities get capabilities => ServerCapabilities(
    http1: true,
    https: true,
    http2: _http2Enabled,
    websocket: true,
    requestStreaming: true,
    responseStreaming: true,
    waitUntil: true,
    edge: false,
    tls: true,
  );

  @override
  String? get url {
    final boundAddress = _boundAddress;
    final boundPort = _boundPort;
    if (boundAddress == null || boundPort == null) {
      return null;
    }

    final protocol = _isSecureBound ? 'https' : 'http';

    final host = _urlHost(boundAddress.address);
    return '$protocol://$host:$boundPort';
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
    if (_useTls) {
      await _bindSecureAndServe();
    } else {
      _server = await _bindHttp();
      _multiProtocolServer = null;
      _http2Enabled = false;
      _attachHttpServer(_server!, isSecure: false);
    }

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

  Future<void> _bindSecureAndServe() async {
    final context = _createSecurityContext();

    try {
      final multi = await MultiProtocolHttpServer.bind(
        _host.resolvedHostname,
        _host.resolvedPort,
        context,
      );

      _multiProtocolServer = multi;
      _server = null;
      _http2Enabled = true;
      _boundAddress = multi.address;
      _boundPort = multi.port;
      _isSecureBound = true;

      multi.startServing(
        (request) {
          unawaited(_handleRequest(request));
        },
        (stream) {
          unawaited(_handleHttp2Stream(stream));
        },
        onError: (error, stackTrace) {
          _host.logError(
            'Transport stream error',
            error is Object ? error : StateError(error.toString()),
            stackTrace,
          );
        },
      );
      return;
    } on UnsupportedError {
      _host.logWarn(
        'HTTP/2 is not available in this runtime TLS stack. '
        'Falling back to HTTPS over HTTP/1.1.',
      );
    }

    _multiProtocolServer = null;
    _http2Enabled = false;
    _server = await _bindSecureHttp11(context);
    _attachHttpServer(_server!, isSecure: true);
  }

  SecurityContext _createSecurityContext() {
    final tls = _host.tlsOptions;
    if (tls == null || !tls.isConfigured) {
      throw StateError(
        'TLS is required for https protocol but no cert/key set',
      );
    }

    final context = SecurityContext();
    _loadCertificate(context, tls.cert!);
    _loadPrivateKey(context, tls.key!, passphrase: tls.passphrase);
    return context;
  }

  Future<HttpServer> _bindSecureHttp11(SecurityContext context) {
    return HttpServer.bindSecure(
      _host.resolvedHostname,
      _host.resolvedPort,
      context,
      shared: _host.reusePort,
    );
  }

  void _attachHttpServer(HttpServer server, {required bool isSecure}) {
    server.autoCompress = false;
    server.idleTimeout = _host.securityLimits.requestTimeout;
    _boundAddress = server.address;
    _boundPort = server.port;
    _isSecureBound = isSecure;

    server.listen(
      (request) {
        unawaited(_handleRequest(request));
      },
      onError: (Object error, StackTrace stackTrace) {
        _host.logError('Transport stream error', error, stackTrace);
      },
      cancelOnError: false,
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
    final isTls = _isSecureBound;
    final runtimeContext = RequestRuntimeContext(
      name: runtimeName,
      protocol: isTls ? 'https' : 'http',
      httpVersion: ioRequest.protocolVersion,
      tls: isTls,
      localAddress: _formatAddress(_boundAddress?.address, _boundPort),
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

  Future<void> _handleHttp2Stream(h2.ServerTransportStream stream) async {
    final waitUntilTasks = <Future<Object?>>[];

    void waitUntil(Future<Object?> task) {
      waitUntilTasks.add(task);
      _host.trackBackgroundTask(task);
    }

    try {
      final incoming = await _readHttp2Request(stream);
      final request = ServerRequest(
        Request(
          incoming.url,
          method: incoming.method,
          headers: incoming.headers,
          body: incoming.body,
        ),
      );

      request.runtime = RequestRuntimeContext(
        name: runtimeName,
        protocol: incoming.scheme,
        httpVersion: '2',
        tls: incoming.scheme == 'https',
        localAddress: _formatAddress(_boundAddress?.address, _boundPort),
        remoteAddress: null,
        waitUntil: waitUntil,
        raw: RuntimeRawContext(dartRequest: stream),
      );
      request.context = <String, Object?>{};
      request.ip = null;
      request.waitUntil = waitUntil;

      final response = await _host.dispatch(request);
      await _writeHttp2Response(stream, response);
    } catch (error, stackTrace) {
      _host.logError('HTTP/2 request handling failed', error, stackTrace);
      await _writeHttp2Response(stream, _transportErrorResponse(error));
    } finally {
      await Future.wait(waitUntilTasks, eagerError: false);
    }
  }

  Future<_Http2IncomingRequest> _readHttp2Request(
    h2.ServerTransportStream stream,
  ) async {
    final iterator = StreamIterator<h2.StreamMessage>(stream.incomingMessages);
    if (!await iterator.moveNext()) {
      throw StateError('HTTP/2 stream is missing request headers.');
    }

    final firstMessage = iterator.current;
    if (firstMessage is! h2.HeadersStreamMessage) {
      throw StateError('First HTTP/2 stream message must be headers.');
    }

    String? method;
    String? scheme;
    String? authority;
    String? path;
    final headers = Headers();

    void readHeaderBlock(List<h2.Header> block) {
      for (final header in block) {
        final name = _decodeHeaderName(header.name);
        final value = _decodeHeaderValue(header.value);
        switch (name) {
          case ':method':
            method = value;
          case ':scheme':
            scheme = value;
          case ':authority':
            authority = value;
          case ':path':
            path = value;
          default:
            headers.append(name, value);
        }
      }
    }

    readHeaderBlock(firstMessage.headers);

    final effectiveMethod = (method ?? 'GET').toUpperCase();
    final allowsBody = _methodAllowsBody(effectiveMethod);
    final maxBodyBytes = _host.securityLimits.maxRequestBodyBytes;
    final bodyBuffer = BytesBuilder(copy: false);
    var totalBodyBytes = 0;
    var bodyOverLimit = false;

    Future<void> consumeMessage(h2.StreamMessage message) async {
      if (message is h2.DataStreamMessage) {
        totalBodyBytes += message.bytes.length;
        if (!bodyOverLimit && totalBodyBytes <= maxBodyBytes) {
          bodyBuffer.add(message.bytes);
        } else {
          bodyOverLimit = true;
        }
      } else if (message is h2.HeadersStreamMessage) {
        readHeaderBlock(message.headers);
      }
    }

    if (!firstMessage.endStream) {
      while (await iterator.moveNext()) {
        final message = iterator.current;
        await consumeMessage(message);
        if (message.endStream) {
          break;
        }
      }
    }

    if (authority != null &&
        authority!.isNotEmpty &&
        !headers.has(HttpHeaders.hostHeader)) {
      headers.append(HttpHeaders.hostHeader, authority!);
    }

    final effectiveScheme = _normalizeProtocol(scheme);
    final uri = _buildHttp2Uri(
      scheme: effectiveScheme,
      authority: authority,
      path: path,
    );
    final body = allowsBody
        ? _buildHttp2Body(
            bytes: bodyBuffer.takeBytes(),
            isOverLimit: bodyOverLimit,
            maxBodyBytes: maxBodyBytes,
            actualBytes: totalBodyBytes,
          )
        : null;

    return _Http2IncomingRequest(
      method: effectiveMethod,
      scheme: effectiveScheme,
      url: uri,
      headers: headers,
      body: body,
    );
  }

  Object? _buildHttp2Body({
    required Uint8List bytes,
    required bool isOverLimit,
    required int maxBodyBytes,
    required int actualBytes,
  }) {
    if (isOverLimit) {
      return Stream<List<int>>.error(
        RequestLimitExceeded(maxBytes: maxBodyBytes, actualBytes: actualBytes),
      );
    }

    if (bytes.isEmpty) {
      return null;
    }

    return bytes;
  }

  String _decodeHeaderName(List<int> bytes) {
    return ascii.decode(bytes, allowInvalid: true).toLowerCase();
  }

  String _decodeHeaderValue(List<int> bytes) {
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _normalizeProtocol(String? scheme) {
    if (scheme == null || scheme.isEmpty) {
      return _isSecureBound ? 'https' : 'http';
    }
    return scheme.toLowerCase();
  }

  Uri _buildHttp2Uri({
    required String scheme,
    required String? authority,
    required String? path,
  }) {
    final normalizedPath = _normalizePath(path);
    final localAuthority = authority ?? _defaultAuthority();
    final uriText = '$scheme://$localAuthority$normalizedPath';
    try {
      return Uri.parse(uriText);
    } on FormatException {
      final parsedAuthority = _parseAuthority(localAuthority);
      final queryIndex = normalizedPath.indexOf('?');
      final pathPart = queryIndex >= 0
          ? normalizedPath.substring(0, queryIndex)
          : normalizedPath;
      final queryPart = queryIndex >= 0
          ? normalizedPath.substring(queryIndex + 1)
          : null;
      return Uri(
        scheme: scheme,
        host: parsedAuthority.host,
        port: parsedAuthority.port,
        path: pathPart,
        query: (queryPart == null || queryPart.isEmpty) ? null : queryPart,
      );
    }
  }

  String _normalizePath(String? path) {
    if (path == null || path.isEmpty) {
      return '/';
    }

    if (path.startsWith('/')) {
      return path;
    }

    if (path.startsWith('?')) {
      return '/$path';
    }

    return '/$path';
  }

  String _defaultAuthority() {
    final host = _boundAddress?.address ?? _host.resolvedHostname;
    final port = _boundPort ?? _host.resolvedPort;
    return '$host:$port';
  }

  Future<void> _writeHttp2Response(
    h2.ServerTransportStream stream,
    Response response,
  ) async {
    final headers = <h2.Header>[
      h2.Header.ascii(':status', response.status.toString()),
    ];

    for (final name in response.headers.names()) {
      if (_isDisallowedHttp2ResponseHeader(name)) {
        continue;
      }

      for (final value in response.headers.getAll(name)) {
        headers.add(h2.Header(ascii.encode(name), utf8.encode(value)));
      }
    }

    final body = response.body;
    if (body == null) {
      stream.outgoingMessages.add(
        h2.HeadersStreamMessage(headers, endStream: true),
      );
      await stream.outgoingMessages.close();
      return;
    }

    stream.outgoingMessages.add(h2.HeadersStreamMessage(headers));
    await for (final chunk in body) {
      if (chunk.isEmpty) {
        continue;
      }
      stream.outgoingMessages.add(h2.DataStreamMessage(chunk));
    }
    await stream.outgoingMessages.close();
  }

  bool _isDisallowedHttp2ResponseHeader(String name) {
    return name == 'connection' ||
        name == 'keep-alive' ||
        name == 'proxy-connection' ||
        name == 'transfer-encoding' ||
        name == 'upgrade';
  }

  Response _transportErrorResponse(Object error) {
    if (error is RequestLimitExceeded) {
      return Response.json(<String, Object>{
        'ok': false,
        'error': 'Request body too large',
        'maxBytes': error.maxBytes,
        'actualBytes': error.actualBytes,
      }, status: 413);
    }

    if (_host.isProduction) {
      return Response.json(const <String, Object>{
        'ok': false,
        'error': 'Internal Server Error',
      }, status: 500);
    }

    return Response.json(<String, Object>{
      'ok': false,
      'error': 'Internal Server Error',
      'details': error.toString(),
    }, status: 500);
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
      final host = _boundAddress?.address ?? _host.resolvedHostname;
      final port = _boundPort ?? _host.resolvedPort;
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

  bool get _useTls => _host.resolvedProtocol == ServerProtocol.https;

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
    final multi = _multiProtocolServer;
    if (server == null && multi == null) {
      return;
    }

    final closeFuture = switch ((server, multi)) {
      (final HttpServer value, null) => value.close(force: force),
      (null, final MultiProtocolHttpServer value) => value.close(force: force),
      _ => Future.wait(<Future<Object?>>[
        if (server != null) server.close(force: force),
        if (multi != null) multi.close(force: force),
      ]),
    };
    if (force || !_host.gracefulShutdown.enabled) {
      await closeFuture;
      _server = null;
      _multiProtocolServer = null;
      _boundAddress = null;
      _boundPort = null;
      _isSecureBound = false;
      return;
    }

    try {
      await closeFuture.timeout(_host.gracefulShutdown.gracefulTimeout);
    } on TimeoutException {
      _host.logWarn(
        'Graceful shutdown timeout reached. Forcing close in '
        '${_host.gracefulShutdown.forceTimeout.inSeconds}s.',
      );
      await switch ((server, multi)) {
        (final HttpServer value, null) =>
          value.close(force: true).timeout(_host.gracefulShutdown.forceTimeout),
        (null, final MultiProtocolHttpServer value) =>
          value.close(force: true).timeout(_host.gracefulShutdown.forceTimeout),
        _ => Future.wait(<Future<Object?>>[
          if (server != null)
            server
                .close(force: true)
                .timeout(_host.gracefulShutdown.forceTimeout),
          if (multi != null)
            multi
                .close(force: true)
                .timeout(_host.gracefulShutdown.forceTimeout),
        ]),
      };
    } finally {
      _server = null;
      _multiProtocolServer = null;
      _boundAddress = null;
      _boundPort = null;
      _isSecureBound = false;
    }
  }
}

final class _Http2IncomingRequest {
  const _Http2IncomingRequest({
    required this.method,
    required this.scheme,
    required this.url,
    required this.headers,
    required this.body,
  });

  final String method;
  final String scheme;
  final Uri url;
  final Headers headers;
  final Object? body;
}

final class _Authority {
  const _Authority(this.host, this.port);

  final String host;
  final int port;
}
