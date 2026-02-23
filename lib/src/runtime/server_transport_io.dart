import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ht/ht.dart' as ht;
import 'package:http2/http2.dart' as h2;
import 'package:http2/multiprotocol_server.dart';

import '../core/config.dart';
import '../request.dart';
import '../types/options.dart';
import '../types/runtime.dart';
import 'server_transport.dart';

const String _ioRequestContextKey = '__io_http_request';

ServerTransport createServerTransport({
  required ServerConfig config,
  required DispatchRequest dispatch,
  required TrackBackgroundTask trackBackgroundTask,
}) {
  return _IoServerTransport(
    config: config,
    dispatch: dispatch,
    trackBackgroundTask: trackBackgroundTask,
  );
}

final class _IoServerTransport implements ServerTransport {
  _IoServerTransport({
    required ServerConfig config,
    required DispatchRequest dispatch,
    required TrackBackgroundTask trackBackgroundTask,
  }) : _config = config,
       _dispatch = dispatch,
       _trackBackgroundTask = trackBackgroundTask;

  final ServerConfig _config;
  final DispatchRequest _dispatch;
  final TrackBackgroundTask _trackBackgroundTask;

  HttpServer? _runtime;
  MultiProtocolHttpServer? _multiProtocol;
  Future<void>? _serveFuture;

  @override
  Runtime get runtime => const Runtime(name: 'dart:io', kind: RuntimeKind.io);

  bool get _http2Enabled => _multiProtocol != null;

  @override
  String get hostname {
    if (_runtime case final runtime?) {
      return runtime.address.host;
    }
    if (_multiProtocol case final multi?) {
      return multi.address.host;
    }
    return _config.hostname;
  }

  @override
  int get port {
    if (_runtime case final runtime?) {
      return runtime.port;
    }
    if (_multiProtocol case final multi?) {
      return multi.port;
    }
    return _config.port;
  }

  @override
  Uri get url => Uri(
    scheme: _config.secure ? 'https' : 'http',
    host: hostname,
    port: port,
  );

  @override
  String get addr {
    final host = hostname.contains(':') ? '[$hostname]' : hostname;
    return '$host:$port';
  }

  @override
  Future<void> serve() {
    return _serveFuture ??= _bindAndListen();
  }

  @override
  Future<void> ready() {
    return _serveFuture ?? Future<void>.value();
  }

  @override
  Future<void> close({required bool force}) async {
    await _runtime?.close(force: force);
    await _multiProtocol?.close(force: force);
    _runtime = null;
    _multiProtocol = null;
  }

  Future<void> _bindAndListen() async {
    if (_config.secure && _config.http2) {
      final tls = _config.tls;
      if (tls != null) {
        try {
          final context = _createSecurityContext(tls);
          final multi = await MultiProtocolHttpServer.bind(
            _config.hostname,
            _config.port,
            context,
          );

          _multiProtocol = multi;
          multi.startServing(
            (request) => unawaited(_handleHttp1(request)),
            (stream) => unawaited(_handleHttp2(stream)),
            onError: (error, stackTrace) {
              Zone.current.handleUncaughtError(error, stackTrace);
            },
          );
          return;
        } catch (_) {
          // Fallback to HTTPS HTTP/1.1 when ALPN/HTTP2 is unavailable.
        }
      }
    }

    final server = await _bindHttp1();
    _runtime = server;
    server.listen(_handleHttp1);
  }

  Future<HttpServer> _bindHttp1() {
    if (_config.tls case final tls?) {
      final securityContext = _createSecurityContext(tls);
      return HttpServer.bindSecure(
        _config.hostname,
        _config.port,
        securityContext,
        shared: _config.reusePort,
      );
    }

    return HttpServer.bind(
      _config.hostname,
      _config.port,
      shared: _config.reusePort,
    );
  }

  SecurityContext _createSecurityContext(TLSOptions tls) {
    final context = SecurityContext(withTrustedRoots: true);
    _loadCertificateChain(context, tls.cert, tls.passphrase);
    _loadPrivateKey(context, tls.key, tls.passphrase);
    return context;
  }

  void _loadCertificateChain(
    SecurityContext context,
    String input,
    String? password,
  ) {
    final file = File(input);
    if (file.existsSync()) {
      context.useCertificateChain(input, password: password);
      return;
    }
    context.useCertificateChainBytes(utf8.encode(input), password: password);
  }

  void _loadPrivateKey(
    SecurityContext context,
    String input,
    String? password,
  ) {
    final file = File(input);
    if (file.existsSync()) {
      context.usePrivateKey(input, password: password);
      return;
    }
    context.usePrivateKeyBytes(utf8.encode(input), password: password);
  }

  Future<void> _handleHttp1(HttpRequest request) async {
    final response = request.response;
    try {
      final method = request.method.toUpperCase();
      final headers = ht.Headers();
      request.headers.forEach((name, values) {
        for (final value in values) {
          headers.append(name, value);
        }
      });

      final body = _methodAllowsBody(method) ? request.cast<List<int>>() : null;

      final fetchRequest = ht.Request(
        _absoluteRequestUri(request),
        method: method,
        headers: headers,
        body: body,
      );

      final ip = request.connectionInfo?.remoteAddress.address ?? '';

      void waitUntil<T>(FutureOr<T> Function() run) {
        final task = Future<T>.sync(run);
        _trackBackgroundTask(
          task.then<Object?>(
            (_) => null,
            onError: (Object _, StackTrace _) => null,
          ),
        );
      }

      final serverRequest = createServerRequest(
        fetchRequest,
        ip: ip,
        waitUntil: waitUntil,
        context: <String, Object?>{_ioRequestContextKey: request},
      );

      final outgoing = await _dispatch(serverRequest);
      if (outgoing.status == HttpStatus.switchingProtocols) {
        return;
      }

      response.statusCode = outgoing.status;
      for (final entry in outgoing.headers) {
        response.headers.add(entry.key, entry.value);
      }

      final bodyStream = outgoing.body;
      if (bodyStream case final stream?) {
        await response.addStream(stream);
      }
      await response.close();
    } catch (error, stackTrace) {
      response.statusCode = HttpStatus.internalServerError;
      response.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/plain; charset=utf-8',
      );
      response.write('Internal Server Error');
      await response.close();
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  Future<void> _handleHttp2(h2.ServerTransportStream stream) async {
    try {
      final incoming = await _readHttp2Request(stream);
      final request = ht.Request(
        incoming.uri,
        method: incoming.method,
        headers: incoming.headers,
        body: incoming.body,
      );

      void waitUntil<T>(FutureOr<T> Function() run) {
        final task = Future<T>.sync(run);
        _trackBackgroundTask(
          task.then<Object?>(
            (_) => null,
            onError: (Object _, StackTrace _) => null,
          ),
        );
      }

      final serverRequest = createServerRequest(
        request,
        waitUntil: waitUntil,
        context: <String, Object?>{'httpVersion': '2'},
      );
      final response = await _dispatch(serverRequest);
      await _writeHttp2Response(stream, response);
    } catch (_) {
      await _writeHttp2Response(
        stream,
        ht.Response.text('Internal Server Error', status: 500),
      );
    }
  }

  Future<_Http2IncomingRequest> _readHttp2Request(
    h2.ServerTransportStream stream,
  ) async {
    final iterator = StreamIterator<h2.StreamMessage>(stream.incomingMessages);
    if (!await iterator.moveNext()) {
      throw StateError('HTTP/2 stream missing headers.');
    }

    final first = iterator.current;
    if (first is! h2.HeadersStreamMessage) {
      throw StateError('HTTP/2 first frame must be headers.');
    }

    String method = 'GET';
    String scheme = _config.secure ? 'https' : 'http';
    String authority = '${_config.hostname}:${_config.port}';
    String path = '/';

    final headers = ht.Headers();
    final body = BytesBuilder(copy: false);

    void readHeaders(List<h2.Header> block) {
      for (final header in block) {
        final name = ascii.decode(header.name, allowInvalid: true);
        final value = utf8.decode(header.value, allowMalformed: true);
        switch (name) {
          case ':method':
            method = value.toUpperCase();
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

    readHeaders(first.headers);

    Future<void> consume(h2.StreamMessage message) async {
      if (message is h2.DataStreamMessage) {
        body.add(message.bytes);
      }
      if (message is h2.HeadersStreamMessage) {
        readHeaders(message.headers);
      }
    }

    if (!first.endStream) {
      while (await iterator.moveNext()) {
        final message = iterator.current;
        await consume(message);
        if (message.endStream) {
          break;
        }
      }
    }

    final uri = _buildHttp2Uri(
      scheme: scheme,
      authority: authority,
      path: path,
    );

    final bodyBytes = body.takeBytes();
    final requestBody = _methodAllowsBody(method) && bodyBytes.isNotEmpty
        ? bodyBytes
        : null;

    return _Http2IncomingRequest(
      method: method,
      uri: uri,
      headers: headers,
      body: requestBody,
    );
  }

  Uri _buildHttp2Uri({
    required String scheme,
    required String authority,
    required String path,
  }) {
    final normalizedPath = path.isEmpty
        ? '/'
        : (path.startsWith('/') || path.startsWith('?') ? path : '/$path');
    final uriText = '$scheme://$authority$normalizedPath';
    try {
      return Uri.parse(uriText);
    } catch (_) {
      return Uri(
        scheme: scheme,
        host: _config.hostname,
        port: port,
        path: normalizedPath,
      );
    }
  }

  Future<void> _writeHttp2Response(
    h2.ServerTransportStream stream,
    ht.Response response,
  ) async {
    if (response.status == HttpStatus.switchingProtocols) {
      response = ht.Response.text(
        'WebSocket over HTTP/2 is not supported.',
        status: 501,
      );
    }

    final headers = <h2.Header>[
      h2.Header.ascii(':status', response.status.toString()),
    ];

    for (final entry in response.headers) {
      final name = entry.key;
      if (_isHttp2ForbiddenHeader(name)) {
        continue;
      }
      headers.add(h2.Header(ascii.encode(name), utf8.encode(entry.value)));
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
      if (chunk.isNotEmpty) {
        stream.outgoingMessages.add(h2.DataStreamMessage(chunk));
      }
    }
    await stream.outgoingMessages.close();
  }

  bool _isHttp2ForbiddenHeader(String name) {
    return name == 'connection' ||
        name == 'keep-alive' ||
        name == 'proxy-connection' ||
        name == 'transfer-encoding' ||
        name == 'upgrade';
  }

  Uri _absoluteRequestUri(HttpRequest request) {
    if (request.requestedUri.hasScheme) {
      return request.requestedUri;
    }

    final scheme = _config.secure || _http2Enabled ? 'https' : 'http';
    final host = request.headers.value(HttpHeaders.hostHeader);
    if (host == null || host.isEmpty) {
      return Uri(
        scheme: scheme,
        host: hostname,
        port: port,
        path: request.uri.path,
        query: request.uri.hasQuery ? request.uri.query : null,
      );
    }

    return Uri.parse('$scheme://$host${request.uri}');
  }

  static bool _methodAllowsBody(String method) {
    return method != 'GET' && method != 'HEAD' && method != 'TRACE';
  }
}

final class _Http2IncomingRequest {
  const _Http2IncomingRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  final String method;
  final Uri uri;
  final ht.Headers headers;
  final Object? body;
}
