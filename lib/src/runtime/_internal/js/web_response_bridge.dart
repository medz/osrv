import 'package:ht/ht.dart' show Response;
import 'package:web/web.dart' as web;

import 'web_stream_bridge.dart';

web.Response webResponseFromHtResponse(
  Response source,
) {
  final headers = web.Headers();
  for (final name in source.headers.names()) {
    final values = source.headers.getAll(name);
    for (final value in values) {
      headers.append(name, value);
    }
  }

  return web.Response(
    source.body == null
        ? null
        : webReadableStreamFromDartByteStream(source.body!),
    web.ResponseInit(
      status: source.status,
      statusText: source.statusText,
      headers: headers,
    ),
  );
}
