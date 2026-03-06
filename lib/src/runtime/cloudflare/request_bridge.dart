import 'dart:js_interop';

import 'package:ht/ht.dart' show Headers, Request;
import 'package:web/web.dart' as web;

@JS()
extension type _IterableHeaders._(JSObject _) implements JSObject {
  external void forEach(JSFunction fn);
}

Future<Request> cloudflareRequestToHtRequest(
  web.Request request,
) async {
  final headers = Headers();
  (request.headers as _IterableHeaders).forEach(
    ((String value, String name, [JSAny? _]) {
      headers.append(name, value);
    }).toJS,
  );

  final body =
      request.body == null ? null : (await request.bytes().toDart).toDart;

  return Request(
    Uri.parse(request.url),
    method: request.method,
    headers: headers,
    body: body == null || body.isEmpty ? null : body,
  );
}
