import 'dart:convert';
import 'dart:typed_data';

import 'package:ht/ht.dart' as ht;

import 'types.dart';

/// Public request type used by osrv handlers.
///
/// It wraps an existing `ht.Request` and carries osrv runtime metadata on the
/// same object.
class ServerRequest implements ht.Request {
  ServerRequest(
    ht.Request request, {
    Uri? url,
    Uri Function()? urlFactory,
    RequestRuntimeContext? runtime,
    RequestRuntimeContext Function()? runtimeFactory,
    Map<String, Object?>? context,
    void Function(ht.Headers headers)? headersInitializer,
    String? ip,
    String? Function()? ipFactory,
    this.waitUntil,
    bool isWebSocketUpgraded = false,
    Object? rawWebSocket,
  }) : _inner = request,
       _url = url,
       _urlFactory = urlFactory,
       _runtime = runtime,
       _runtimeFactory = runtimeFactory,
       _context = context,
       _headersInitializer = headersInitializer,
       _ip = ip,
       _ipFactory = ipFactory,
       _isWebSocketUpgraded = isWebSocketUpgraded,
       _rawWebSocket = rawWebSocket;

  final ht.Request _inner;
  static const Object _sentinel = Object();

  Uri? _url;
  Uri Function()? _urlFactory;
  RequestRuntimeContext? _runtime;
  RequestRuntimeContext Function()? _runtimeFactory;
  Map<String, Object?>? _context;
  String? _ip;
  String? Function()? _ipFactory;
  void Function(ht.Headers headers)? _headersInitializer;
  WaitUntil? waitUntil;

  Map<String, Object?> get context => _context ??= <String, Object?>{};

  set context(Map<String, Object?> value) {
    _context = value;
  }

  RequestRuntimeContext? get runtime {
    final runtime = _runtime;
    if (runtime != null) {
      return runtime;
    }

    final factory = _runtimeFactory;
    if (factory == null) {
      return null;
    }

    final resolved = factory();
    _runtime = resolved;
    _runtimeFactory = null;
    return resolved;
  }

  set runtime(RequestRuntimeContext? value) {
    _runtime = value;
    _runtimeFactory = null;
  }

  void setRuntimeFactory(RequestRuntimeContext Function() factory) {
    _runtime = null;
    _runtimeFactory = factory;
  }

  String? get ip {
    final ip = _ip;
    if (ip != null) {
      return ip;
    }

    final factory = _ipFactory;
    if (factory == null) {
      return null;
    }

    final resolved = factory();
    _ip = resolved;
    _ipFactory = null;
    return resolved;
  }

  set ip(String? value) {
    _ip = value;
    _ipFactory = null;
  }

  void setIpFactory(String? Function() factory) {
    _ip = null;
    _ipFactory = factory;
  }

  bool _isWebSocketUpgraded;
  Object? _rawWebSocket;

  bool get isWebSocketUpgraded => _isWebSocketUpgraded;

  void markWebSocketUpgraded() {
    _isWebSocketUpgraded = true;
  }

  void setRawWebSocket(Object socket) {
    _rawWebSocket = socket;
  }

  Object? takeRawWebSocket() {
    final socket = _rawWebSocket;
    _rawWebSocket = null;
    return socket;
  }

  @override
  Uri get url {
    final resolved = _url;
    if (resolved != null) {
      return resolved;
    }

    final factory = _urlFactory;
    if (factory == null) {
      return _inner.url;
    }

    final next = factory();
    _url = next;
    _urlFactory = null;
    return next;
  }

  @override
  String get method => _inner.method;

  @override
  ht.Headers get headers {
    _ensureHeadersInitialized();
    return _inner.headers;
  }

  @override
  get bodyData => _inner.bodyData;

  @override
  String? get bodyMimeTypeHint {
    _ensureHeadersInitialized();
    return _inner.bodyMimeTypeHint;
  }

  @override
  Stream<Uint8List>? get body => _inner.body;

  @override
  bool get bodyUsed => _inner.bodyUsed;

  @override
  Future<Uint8List> bytes() => _inner.bytes();

  @override
  Future<String> text([Encoding encoding = utf8]) => _inner.text(encoding);

  @override
  Future<T> json<T>() => _inner.json<T>();

  @override
  Future<ht.Blob> blob() => _inner.blob();

  @override
  ServerRequest clone() {
    _ensureHeadersInitialized();
    return ServerRequest(
      _inner.clone(),
      url: _url,
      urlFactory: _urlFactory,
      runtime: _runtime,
      runtimeFactory: _runtimeFactory,
      context: _context == null ? null : Map<String, Object?>.from(_context!),
      headersInitializer: null,
      ip: _ip,
      ipFactory: _ipFactory,
      waitUntil: waitUntil,
      isWebSocketUpgraded: _isWebSocketUpgraded,
      rawWebSocket: _rawWebSocket,
    );
  }

  @override
  ServerRequest copyWith({
    Uri? url,
    String? method,
    ht.Headers? headers,
    Object? body = _sentinel,
  }) {
    _ensureHeadersInitialized();
    final resolvedUrl = url ?? _url;
    final next = identical(body, _sentinel)
        ? _inner.copyWith(url: resolvedUrl, method: method, headers: headers)
        : _inner.copyWith(
            url: resolvedUrl,
            method: method,
            headers: headers,
            body: body,
          );

    return ServerRequest(
      next,
      url: resolvedUrl,
      urlFactory: resolvedUrl == null ? _urlFactory : null,
      runtime: _runtime,
      runtimeFactory: _runtimeFactory,
      context: _context == null ? null : Map<String, Object?>.from(_context!),
      headersInitializer: null,
      ip: _ip,
      ipFactory: _ipFactory,
      waitUntil: waitUntil,
      isWebSocketUpgraded: _isWebSocketUpgraded,
      rawWebSocket: _rawWebSocket,
    );
  }

  void _ensureHeadersInitialized() {
    final initializer = _headersInitializer;
    if (initializer == null) {
      return;
    }

    _headersInitializer = null;
    initializer(_inner.headers);
  }
}
