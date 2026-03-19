import 'dart:async';
import 'dart:convert';

import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/cloudflare.dart';
import 'package:web/web.dart' as web;
import 'package:web_socket/web_socket.dart' as ws;

void main() {
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
          });
        case '/echo':
          return Response.json({
            'method': request.method.value,
            'path': uri.path,
            'query': uri.queryParameters['mode'],
            'header': request.headers.get('x-test'),
            'body': await request.text(),
          });
        case '/stream':
          return Response(
            Stream<List<int>>.fromIterable([
              utf8.encode('hello '),
              utf8.encode('cloudflare'),
            ]),
            ResponseInit(headers: Headers()..set('x-stream', 'yes')),
          );
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
        case '/raw-101':
          return Response(null, const ResponseInit(status: 101));
        case '/error':
          throw StateError('boom');
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
      final request = context
          .extension<CloudflareRuntimeExtension<Object?, web.Request>>()
          ?.request;
      final path = request == null ? null : Uri.parse(request.url).path;
      if (path != '/error') {
        return null;
      }

      return Response(
        'handled ${context.runtime.name}',
        ResponseInit(status: 418),
      );
    },
  );

  defineFetchExport(server);
}
