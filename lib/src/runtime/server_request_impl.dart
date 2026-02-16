import 'dart:convert';
import 'dart:typed_data';

import 'package:ht/ht.dart' as ht;

import '../request.dart';
import '../types.dart';

ServerRequest createServerRequest(
  ht.Request request, {
  Uri Function()? urlResolver,
  RequestRuntimeContext? Function()? runtimeResolver,
  String? Function()? ipResolver,
  WaitUntil? waitUntil,
  Map<String, Object?>? context,
}) {
  return _ServerRequestImpl(
    request,
    urlResolver: urlResolver,
    runtimeResolver: runtimeResolver,
    ipResolver: ipResolver,
    waitUntil: waitUntil,
    context: context,
  );
}

final class _ServerRequestImpl implements ServerRequest {
  _ServerRequestImpl(
    this._inner, {
    Uri Function()? urlResolver,
    RequestRuntimeContext? Function()? runtimeResolver,
    String? Function()? ipResolver,
    WaitUntil? waitUntil,
    Map<String, Object?>? context,
  }) : _urlResolver = urlResolver,
       _runtimeResolver = runtimeResolver,
       _ipResolver = ipResolver,
       _waitUntil = waitUntil,
       _context = context ?? <String, Object?>{};

  final ht.Request _inner;
  final Uri Function()? _urlResolver;
  final RequestRuntimeContext? Function()? _runtimeResolver;
  final String? Function()? _ipResolver;
  final WaitUntil? _waitUntil;
  final Map<String, Object?> _context;

  @override
  Uri get url => _urlResolver?.call() ?? _inner.url;

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
  Map<String, Object?> get context => _context;

  @override
  RequestRuntimeContext? get runtime => _runtimeResolver?.call();

  @override
  String? get ip => _ipResolver?.call();

  @override
  WaitUntil? get waitUntil => _waitUntil;

  @override
  ServerRequest clone() {
    final cloned = _inner.copyWith(url: url);
    return _ServerRequestImpl(cloned);
  }

  @override
  ServerRequest copyWith({
    Uri? url,
    String? method,
    ht.Headers? headers,
    Object? body = serverRequestNoBody,
  }) {
    final resolvedUrl = url ?? this.url;
    final next = identical(body, serverRequestNoBody)
        ? _inner.copyWith(url: resolvedUrl, method: method, headers: headers)
        : _inner.copyWith(
            url: resolvedUrl,
            method: method,
            headers: headers,
            body: body,
          );
    return _ServerRequestImpl(next);
  }
}
