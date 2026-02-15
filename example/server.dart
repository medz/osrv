import 'dart:async';

import 'package:osrv/osrv.dart';

Future<void> main() async {
  final server = Server(
    fetch: (request) async {
      if (request.url.path == '/echo') {
        return Response.text(await request.text());
      }

      if (request.url.path == '/error') {
        throw StateError('example forced error');
      }

      if (request.url.path == '/ws') {
        final socket = await upgradeWebSocket(request);
        unawaited(_runWebSocketEcho(socket));
        return socket.toResponse();
      }

      final payload = <String, Object?>{
        'ok': true,
        'path': request.url.path,
        'url': request.url.toString(),
        'method': request.method,
        'runtime': request.runtime?.name,
        'ip': request.ip,
      };

      return Response.json(payload);
    },
    middleware: <Middleware>[
      (request, next) async {
        request.context['start'] = DateTime.now().toUtc().toIso8601String();
        final response = await next();
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
