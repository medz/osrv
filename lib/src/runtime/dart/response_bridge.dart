// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:ht/ht.dart' show Response;

Future<void> writeHtResponseToDartHttpResponse(
  Response source,
  HttpResponse target,
) async {
  target.statusCode = source.status;
  if (source.statusText.isNotEmpty) {
    target.reasonPhrase = source.statusText;
  }

  for (final MapEntry(:key, :value) in source.headers.entries()) {
    target.headers.add(key, value);
  }

  final body = source.body;
  if (body == null) {
    await target.close();
    return;
  }

  await target.addStream(body);
  await target.close();
}
