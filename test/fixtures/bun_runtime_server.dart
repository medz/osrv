import 'dart:async';
import 'dart:convert';

import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/bun.dart';

Future<void> main() async {
  late final Runtime runtime;

  final server = Server(
    fetch: (request, context) async {
      switch (request.url.path) {
        case '/echo':
          return Response.json({
            'method': request.method,
            'path': request.url.path,
            'query': request.url.queryParameters['mode'],
            'header': request.headers.get('x-test'),
            'body': await request.text(),
            'hasBunRequest':
                context.extension<BunRuntimeExtension>()?.request != null,
          });
        case '/stream':
          return Response(
            body: Stream<List<int>>.fromIterable([
              utf8.encode('hello '),
              utf8.encode('bun'),
            ]),
            headers: Headers()..set('x-stream', 'yes'),
          );
        case '/error':
          throw StateError('boom');
        case '/wait-close':
          context.waitUntil(
            Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          unawaited(
            Future<void>(() async {
              await Future<void>.delayed(Duration.zero);
              await runtime.close();
            }),
          );
          return Response.text('closing');
        default:
          return Response.text(
            'hello from ${context.runtime.name}',
            headers: Headers()..set('x-runtime', context.runtime.name),
          );
      }
    },
    onError: (error, stackTrace, context) {
      return Response.text(
        'handled ${context.runtime.name}',
        status: 418,
      );
    },
  );

  runtime = await serve(
    server,
    const BunRuntimeConfig(
      host: '127.0.0.1',
      port: 0,
    ),
  );

  print('URL:${runtime.url}');
  await runtime.closed;
}
