// ignore_for_file: public_member_api_docs

import 'dart:js_interop';

import 'package:ht/ht.dart' show Response, ResponseType;
import 'package:web/web.dart' as web;

import 'web_stream_bridge.dart';

web.Response webInternalServerErrorResponse() {
  return web.Response(
    'Internal Server Error'.toJS,
    web.ResponseInit(status: 500, statusText: 'Internal Server Error'),
  );
}

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

web.Response webResponseFromHtResponseRejectingRaw101(Response source) {
  if (source.status == 101) {
    return webInternalServerErrorResponse();
  }

  return webResponseFromHtResponse(source);
}

web.Headers _copyHeaders(Response source) {
  final headers = web.Headers();
  for (final MapEntry(:key, :value) in source.headers.entries()) {
    headers.append(key, value);
  }
  return headers;
}
