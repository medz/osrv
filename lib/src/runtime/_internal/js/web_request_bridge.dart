// ignore_for_file: public_member_api_docs

@JS()
library;

import 'dart:js_interop';

import 'package:ht/ht.dart' show Headers, Request;
import 'package:web/web.dart' as web;

import 'web_stream_bridge.dart';

@JS()
extension type _IterableHeaders._(JSObject _) implements JSObject {
  external void forEach(JSFunction fn);
}

Request htRequestFromWebRequest(web.Request request) {
  final headers = Headers();
  (request.headers as _IterableHeaders).forEach(
    ((String value, String name, [JSAny? _]) {
      headers.append(name, value);
    }).toJS,
  );

  return Request(
    Uri.parse(request.url),
    method: request.method,
    headers: headers,
    body: request.body == null
        ? null
        : dartByteStreamFromWebReadableStream(request.body!),
  );
}
