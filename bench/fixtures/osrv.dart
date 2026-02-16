import 'dart:async';

import 'package:osrv/osrv.dart';

Future<void> main(List<String> args) async {
  final server = Server(
    hostname: '127.0.0.1',
    port: _readPort(args),
    silent: true,
    fetch: (request) async {
      if (request.method == 'GET' && request.url.path == '/text') {
        return Response.text('ok');
      }

      if (request.method == 'POST' && request.url.path == '/json') {
        final decoded = await request.json<Object?>();
        return Response.json(<String, Object?>{
          'ok': true,
          'type': decoded.runtimeType.toString(),
        });
      }

      return Response.text('not found', status: 404);
    },
  );

  await server.serve();
  await Completer<void>().future;
}

int _readPort(List<String> args) {
  final fromArg = _readIntArg(args, '--port');
  if (fromArg != null) {
    return fromArg;
  }
  return 3000;
}

int? _readIntArg(List<String> args, String name) {
  for (final arg in args) {
    if (arg.startsWith('$name=')) {
      return int.tryParse(arg.substring(name.length + 1));
    }
  }
  return null;
}
