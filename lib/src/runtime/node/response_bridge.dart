import 'package:ht/ht.dart' show Response;

import 'http_host.dart';

final class NodeTransportWriteError implements Exception {
  const NodeTransportWriteError(this.cause);

  final Object cause;
}

Future<void> writeHtResponseToNodeServerResponse(
  Response source,
  NodeServerResponseHost target,
) async {
  try {
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

    Object? streamError;
    StackTrace? streamStackTrace;

    try {
      await for (final chunk in body) {
        if (chunk.isEmpty) {
          continue;
        }

        await nodeServerResponseWrite(target, chunk);
      }
    } catch (error, stackTrace) {
      streamError = error;
      streamStackTrace = stackTrace;
    }

    try {
      await nodeServerResponseEnd(target);
    } catch (error, stackTrace) {
      if (streamError == null) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    if (streamError != null) {
      Error.throwWithStackTrace(streamError, streamStackTrace!);
    }
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(NodeTransportWriteError(error), stackTrace);
  }
}
