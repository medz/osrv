import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'test_support.dart';

Future<void> expectHelloEndpoint(
  Uri baseUri, {
  required String expectedBody,
  required String expectedRuntimeHeader,
}) async {
  final response = await send(
    baseUri.resolve('/hello'),
    headers: {'accept': 'text/plain'},
  );
  expect(response.statusCode, 200);
  expect(await response.transform(utf8.decoder).join(), expectedBody);
  expect(response.headers.value('x-runtime'), expectedRuntimeHeader);
}

Future<void> expectWebSocketEcho(
  Uri baseUri, {
  String path = '/chat',
  String protocol = 'chat',
  String connectedMessage = 'connected',
  String outboundMessage = 'ping',
  String echoedMessage = 'echo:ping',
}) async {
  final webSocket = await WebSocket.connect(
    baseUri
        .replace(scheme: 'ws', path: path, query: '', fragment: '')
        .toString(),
    protocols: [protocol],
  );
  addTearDown(() async {
    if (webSocket.closeCode == null) {
      await webSocket.close();
    }
  });

  final events = StreamIterator<Object?>(webSocket);
  expect(webSocket.protocol, protocol);
  expect(await events.moveNext().timeout(const Duration(seconds: 5)), isTrue);
  expect(events.current, connectedMessage);

  webSocket.add(outboundMessage);
  expect(await events.moveNext().timeout(const Duration(seconds: 5)), isTrue);
  expect(events.current, echoedMessage);

  await webSocket.close();
  await Future<void>.delayed(const Duration(milliseconds: 50));
}
