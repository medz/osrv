// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:ht/ht.dart' show Response;

Future<void> writeHtResponseToDartHttpResponse(
  Response source,
  HttpResponse target,
) async {
  target.statusCode = source.status;
  target.reasonPhrase = source.statusText;

  for (final name in source.headers.names()) {
    final values = source.headers.getAll(name);
    if (values.isEmpty) {
      continue;
    }

    target.headers.set(name, values);
  }

  final body = source.body;
  if (body == null) {
    await target.close();
    return;
  }

  await target.addStream(body);
  await target.close();
}
