import 'dart:async';
import 'dart:convert';

import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/bun.dart';
import 'package:web_socket/web_socket.dart' as ws;

Future<void> main() async {
  late final Runtime runtime;

  final server = Server(
    fetch: (request, context) async {
      final uri = Uri.parse(request.url);

      switch (uri.path) {
        case '/meta':
          final webSocket = context.webSocket;
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
            'request': {
              'hasWebSocket': webSocket != null,
              'upgrade': webSocket?.isUpgradeRequest ?? false,
            },
          });
        case '/chat':
          final webSocket = context.webSocket;
          if (webSocket == null || !webSocket.isUpgradeRequest) {
            return Response(
              'upgrade required',
              const ResponseInit(status: 426),
            );
          }

          return webSocket.accept(protocol: 'chat', (socket) async {
            socket.sendText('connected');

            await for (final event in socket.events) {
              switch (event) {
                case ws.TextDataReceived(text: final text):
                  socket.sendText('echo:$text');
                case ws.BinaryDataReceived():
                case ws.CloseReceived():
                  break;
              }
            }
          });
        case '/echo':
          return Response.json({
            'method': request.method.value,
            'path': uri.path,
            'query': uri.queryParameters['mode'],
            'header': request.headers.get('x-test'),
            'body': await request.text(),
            'hasBunRequest':
                context.extension<BunRuntimeExtension>()?.request != null,
          });
        case '/stream':
          return Response(
            Stream<List<int>>.fromIterable([
              utf8.encode('hello '),
              utf8.encode('bun'),
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
}
