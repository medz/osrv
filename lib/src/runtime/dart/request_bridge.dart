import 'dart:io';

import 'package:ht/ht.dart' show Headers, Request;

Future<Request> dartRequestFromHttpRequest(HttpRequest request) async {
  final headers = Headers();
  request.headers.forEach((name, values) {
    for (final value in values) {
      headers.append(name, value);
    }
  });

  final body = await request.fold<List<int>>(<int>[], (buffer, chunk) {
    buffer.addAll(chunk);
    return buffer;
  });

  return Request(
    request.requestedUri,
    method: request.method,
    headers: headers,
    body: body.isEmpty ? null : body,
  );
}
