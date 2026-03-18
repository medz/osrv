import 'dart:async';
import 'dart:convert';

import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/deno.dart';

Future<void> main() async {
  late final Runtime runtime;
  var onStartHasDeno = false;
  var onStartHasServer = false;
  var onStopHasDeno = false;
  var onStopHasServer = false;

  final server = Server(
    fetch: (request, context) async {
      final uri = Uri.parse(request.url);

      switch (uri.path) {
        case '/meta':
          return Response.json({
            'runtime': context.runtime.name,
            'kind': context.runtime.kind,
            'capabilities': {
              'streaming': context.capabilities.streaming,
              'websocket': context.capabilities.websocket,
              'fileSystem': context.capabilities.fileSystem,
              'backgroundTask': context.capabilities.backgroundTask,
              'rawTcp': context.capabilities.rawTcp,
              'nodeCompat': context.capabilities.nodeCompat,
            },
            'lifecycle': {
              'onStartHasDeno': onStartHasDeno,
              'onStartHasServer': onStartHasServer,
            },
          });
        case '/echo':
          return Response.json({
            'method': request.method.value,
            'path': uri.path,
            'query': uri.queryParameters['mode'],
            'header': request.headers.get('x-test'),
            'body': await request.text(),
            'hasDenoRequest':
                context.extension<DenoRuntimeExtension>()?.request != null,
          });
        case '/stream':
          return Response(
            Stream<List<int>>.fromIterable([
              utf8.encode('hello '),
              utf8.encode('deno'),
            ]),
            ResponseInit(headers: Headers()..set('x-stream', 'yes')),
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
          return Response('closing');
        default:
          return Response(
            'hello from ${context.runtime.name}',
            ResponseInit(
              headers: Headers()..set('x-runtime', context.runtime.name),
            ),
          );
      }
    },
    onStart: (context) {
      final extension = context.extension<DenoRuntimeExtension>();
      onStartHasDeno = extension?.deno != null;
      onStartHasServer = extension?.server != null;
    },
    onStop: (context) {
      final extension = context.extension<DenoRuntimeExtension>();
      onStopHasDeno = extension?.deno != null;
      onStopHasServer = extension?.server != null;
    },
    onError: (error, stackTrace, context) {
      return Response(
        'handled ${context.runtime.name}',
        ResponseInit(status: 418),
      );
    },
  );

  runtime = await serve(server, host: '127.0.0.1', port: 0);

  print('URL:${runtime.url}');
  await runtime.closed;
  print(
    'LIFECYCLE:${jsonEncode({'onStopHasDeno': onStopHasDeno, 'onStopHasServer': onStopHasServer})}',
  );
}
