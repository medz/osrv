import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ht/ht.dart' as ht;

typedef WaitUntil = void Function<T>(FutureOr<T> Function() run);

extension type const RequestContext(Map<String, Object?> _)
    implements Map<String, Object?> {}

abstract interface class ServerRequest implements ht.Request {
  RequestContext get context;
  String get ip;
  WaitUntil get waitUntil;
}

ServerRequest createServerRequest(
  ht.Request request, {
  Map<String, Object?>? context,
  String? ip,
  WaitUntil? waitUntil,
}) {
  return _ServerRequestImpl(
    request,
    context: context,
    ip: ip,
    waitUntil: waitUntil,
  );
}

final class _ServerRequestImpl implements ServerRequest {
  _ServerRequestImpl(
    this._inner, {
    Map<String, Object?>? context,
    String? ip,
    WaitUntil? waitUntil,
  }) : _context = RequestContext(context ?? <String, Object?>{}),
       _ip = ip ?? '',
       _waitUntil = waitUntil ?? _noopWaitUntil;

  static void _noopWaitUntil<T>(FutureOr<T> Function() run) {
    Future<T>.sync(run);
  }

  final ht.Request _inner;
  final RequestContext _context;
  final String _ip;
  final WaitUntil _waitUntil;

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
  RequestContext get context => _context;

  @override
  String get ip => _ip;

  @override
  WaitUntil get waitUntil => _waitUntil;

  @override
  ServerRequest clone() {
    final cloned = _inner.copyWith(url: url);
    return _ServerRequestImpl(
      cloned,
      context: Map<String, Object?>.from(_context),
      ip: _ip,
      waitUntil: _waitUntil,
    );
  }

  @override
  ServerRequest copyWith({
    Uri? url,
    String? method,
    ht.Headers? headers,
    Object? body = _noBody,
  }) {
    final next = identical(body, _noBody)
        ? _inner.copyWith(url: url, method: method, headers: headers)
        : _inner.copyWith(
            url: url,
            method: method,
            headers: headers,
            body: body,
          );

    return _ServerRequestImpl(
      next,
      context: Map<String, Object?>.from(_context),
      ip: _ip,
      waitUntil: _waitUntil,
    );
  }
}

const Object _noBody = Object();
