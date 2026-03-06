import 'dart:js_interop';

import 'package:ht/ht.dart' show Response;
import 'package:web/web.dart' as web;

Future<web.Response> cloudflareResponseFromHtResponse(
  Response source,
) async {
  final headers = web.Headers();
  for (final name in source.headers.names()) {
    final values = source.headers.getAll(name);
    for (final value in values) {
      headers.append(name, value);
    }
  }

  final body = source.body == null ? null : await source.bytes();

  return web.Response(
    body == null || body.isEmpty ? null : body.toJS,
    web.ResponseInit(
      status: source.status,
      statusText: source.statusText,
      headers: headers,
    ),
  );
}
