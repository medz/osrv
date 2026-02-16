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
    RequestRuntimeContext? runtime,
    Map<String, Object?>? context,
    String? ip,
    this.waitUntil,
    bool isWebSocketUpgraded = false,
    Object? rawWebSocket,
  }) : _inner = request,
       _runtime = runtime,
       _context = context,
       _ip = ip,
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

  void deferRuntime(RequestRuntimeContext Function() factory) {
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

  void deferIp(String? Function() factory) {
    _ip = null;
    _ipFactory = factory;
  }

  void deferUrl(Uri Function() factory) {
    _url = null;
    _urlFactory = factory;
  }

  void deferHeaders(void Function(ht.Headers headers) initializer) {
    _headersInitializer = initializer;
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
    final cloned = ServerRequest(
      _inner.clone(),
      runtime: _runtime,
      context: _context == null ? null : Map<String, Object?>.from(_context!),
      ip: _ip,
      waitUntil: waitUntil,
      isWebSocketUpgraded: _isWebSocketUpgraded,
      rawWebSocket: _rawWebSocket,
    );
    cloned._url = _url;
    cloned._urlFactory = _urlFactory;
    cloned._runtimeFactory = _runtimeFactory;
    cloned._ipFactory = _ipFactory;
    return cloned;
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

    final copied = ServerRequest(
      next,
      runtime: _runtime,
      context: _context == null ? null : Map<String, Object?>.from(_context!),
      ip: _ip,
      waitUntil: waitUntil,
      isWebSocketUpgraded: _isWebSocketUpgraded,
      rawWebSocket: _rawWebSocket,
    );
    copied._url = resolvedUrl;
    if (resolvedUrl == null) {
      copied._urlFactory = _urlFactory;
    }
    copied._runtimeFactory = _runtimeFactory;
    copied._ipFactory = _ipFactory;
    return copied;
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
