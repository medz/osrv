import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:web_socket/web_socket.dart' as ws;

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
  int expectedCloseCode = 1000,
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

  await webSocket.close(1000, 'client done');
  expect(
    await events.moveNext().timeout(
      const Duration(seconds: 5),
      onTimeout: () => true,
    ),
    isFalse,
    reason: 'WebSocket stream should finish after the close handshake.',
  );
  expect(
    webSocket.closeCode,
    expectedCloseCode,
    reason: 'WebSocket close handshake should complete cleanly.',
  );
}

Future<void> expectObservableLocalClose({
  required Stream<ws.WebSocketEvent> events,
  required Future<void> Function() startLocalClose,
  required FutureOr<void> Function() triggerTerminalClose,
  required int expectedCode,
  required String expectedReason,
}) async {
  final eventsExpectation = expectLater(
    events,
    emitsInOrder([
      isA<ws.CloseReceived>()
          .having((event) => event.code, 'code', expectedCode)
          .having((event) => event.reason, 'reason', expectedReason),
      emitsDone,
    ]),
  );

  final closeFuture = startLocalClose();
  await triggerTerminalClose();

  await closeFuture;
  await eventsExpectation;
}
