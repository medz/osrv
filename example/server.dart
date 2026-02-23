import 'dart:async';

import 'package:osrv/osrv.dart';

Future<void> main() async {
  final server = Server(
    fetch: (request) async {
      if (request.url.path == '/echo') {
        return Response.text(await request.text());
      }

      if (request.url.path == '/ws') {
        final socket = await upgradeWebSocket(request);
        unawaited(_runWebSocketEcho(socket));
        return socket.toResponse();
      }

      return Response.json(<String, Object?>{
        'ok': true,
        'path': request.url.path,
        'method': request.method,
        'ip': request.ip,
      });
    },
    middleware: <Middleware>[
      (request, next) async {
        final response = await next(request);
        response.headers.set('x-osrv', '1');
        return response;
      },
    ],
  );

  await server.serve();
}

Future<void> _runWebSocketEcho(ServerWebSocket socket) async {
  try {
    await for (final message in socket.messages) {
      if (message is String) {
        await socket.sendText('echo:$message');
      } else if (message is List<int>) {
        await socket.sendBytes(message);
      }
    }
  } finally {
    await socket.close();
  }
}
