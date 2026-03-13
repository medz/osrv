// ignore_for_file: public_member_api_docs

import 'package:ht/ht.dart' show Response, ResponseType;
import 'package:web/web.dart' as web;

import 'web_stream_bridge.dart';

web.Response webResponseFromHtResponse(Response source) {
  if (source.type == ResponseType.error) {
    return web.Response.error();
  }

  final headers = _copyHeaders(source);

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

web.Headers _copyHeaders(Response source) {
  final headers = web.Headers();
  for (final MapEntry(:key, :value) in source.headers.entries()) {
    headers.append(key, value);
  }
  return headers;
}
