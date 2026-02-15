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
    this.runtime,
    Map<String, Object?>? context,
    this.ip,
    this.waitUntil,
    bool isWebSocketUpgraded = false,
    Object? rawWebSocket,
  }) : _inner = request,
       context = context ?? <String, Object?>{},
       _isWebSocketUpgraded = isWebSocketUpgraded,
       _rawWebSocket = rawWebSocket;

  final ht.Request _inner;
  static const Object _sentinel = Object();

  RequestRuntimeContext? runtime;
  Map<String, Object?> context;
  String? ip;
  WaitUntil? waitUntil;

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
  Uri get url => _inner.url;

  @override
  String get method => _inner.method;

  @override
  ht.Headers get headers => _inner.headers;

  @override
  get bodyData => _inner.bodyData;

  @override
  String? get bodyMimeTypeHint => _inner.bodyMimeTypeHint;

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
    return ServerRequest(
      _inner.clone(),
      runtime: runtime,
      context: Map<String, Object?>.from(context),
      ip: ip,
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
    final next = identical(body, _sentinel)
        ? _inner.copyWith(url: url, method: method, headers: headers)
        : _inner.copyWith(
            url: url,
            method: method,
            headers: headers,
            body: body,
          );

    return ServerRequest(
      next,
      runtime: runtime,
      context: Map<String, Object?>.from(context),
      ip: ip,
      waitUntil: waitUntil,
      isWebSocketUpgraded: _isWebSocketUpgraded,
      rawWebSocket: _rawWebSocket,
    );
  }
}
