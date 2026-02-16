import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> args) async {
  final server = await shelf_io.serve(_handler, '127.0.0.1', _readPort(args));
  server.autoCompress = false;
  await Completer<void>().future;
}

Future<Response> _handler(Request request) async {
  if (request.method == 'GET' && request.requestedUri.path == '/text') {
    return Response.ok('ok');
  }

  if (request.method == 'POST' && request.requestedUri.path == '/json') {
    final decoded = jsonDecode(await request.readAsString());
    return Response.ok(
      jsonEncode(<String, Object?>{
        'ok': true,
        'type': decoded.runtimeType.toString(),
      }),
      headers: const <String, String>{
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
      },
    );
  }

  return Response.notFound('not found');
}

int _readPort(List<String> args) {
  final fromArg = _readIntArg(args, '--port');
  if (fromArg != null) {
    return fromArg;
  }
  final raw = Platform.environment['PORT'];
  final parsed = raw == null ? null : int.tryParse(raw);
  return parsed ?? 3000;
}

int? _readIntArg(List<String> args, String name) {
  for (final arg in args) {
    if (arg.startsWith('$name=')) {
      return int.tryParse(arg.substring(name.length + 1));
    }
  }
  return null;
}
