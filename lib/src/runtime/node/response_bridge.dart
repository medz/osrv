import 'package:ht/ht.dart' show Response;

import 'http_host.dart';

Future<void> writeHtResponseToNodeServerResponse(
  Response source,
  NodeServerResponseHost target,
) async {
  nodeServerResponseSetStatus(
    target,
    status: source.status,
    statusText: source.statusText,
  );

  for (final name in source.headers.names()) {
    final values = source.headers.getAll(name);
    if (values.isEmpty) {
      continue;
    }

    nodeServerResponseSetHeader(
      target,
      name,
      values.length == 1 ? values.single : values,
    );
  }

  final body = source.body;
  if (body == null) {
    await nodeServerResponseEnd(target);
    return;
  }

  try {
    await for (final chunk in body) {
      if (chunk.isEmpty) {
        continue;
      }

      await nodeServerResponseWrite(target, chunk);
    }
  } finally {
    await nodeServerResponseEnd(target);
  }
}
