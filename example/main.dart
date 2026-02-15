import 'dart:io';

import 'package:osrv/osrv.dart';

Future<void> main() async {
  final server = Server(
    fetch: (request) async {
      final payload = <String, Object?>{
        'ok': true,
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
  stdout.writeln('server listening on ${server.url}');
}
