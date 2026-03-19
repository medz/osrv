import 'dart:async';

import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/node.dart';
import 'package:osrv/websocket.dart';

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
                case TextDataReceived(text: final text):
                  socket.sendText('echo:$text');
                case BinaryDataReceived():
                case CloseReceived():
                  break;
              }
            }
          });
        case '/chat-requested-protocol':
          final webSocket = context.webSocket;
          if (webSocket == null || !webSocket.isUpgradeRequest) {
            return Response(
              'upgrade required',
              const ResponseInit(status: 426),
            );
          }

          return webSocket.accept(
            protocol: webSocket.requestedProtocols.first,
            (socket) async {
              socket.sendText('connected');
              await socket.events.drain<void>();
            },
          );
        case '/raw-101-upgrade':
          return Response(null, const ResponseInit(status: 101));
        case '/upgrade-http-response':
          return Response(
            'bad upgrade',
            ResponseInit(
              status: 418,
              statusText: 'bad\r\nInjected: nope',
              headers: Headers()..set('x-safe', 'ok'),
            ),
          );
        case '/close-runtime':
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
  );

  runtime = await serve(server, host: '127.0.0.1', port: 0);

  print('URL:${runtime.url}');
  await runtime.closed;
  print('CLOSED');
}
