@TestOn('node')
library;

import 'dart:js_interop';

import 'package:osrv/src/runtime/bun/interop.dart' show BunServerWebSocketHost;
import 'package:osrv/src/runtime/bun/server_web_socket.dart';
import 'package:test/test.dart';
import 'package:web_socket/web_socket.dart' as ws;

@JSExport()
final class _FakeBunSocket {
  int? closeCode;
  String? closeReason;

  void send(JSAny? data) {
    data;
  }

  void close([JSAny? code, JSAny? reason]) {
    closeCode = (code as JSNumber?)?.toDartInt;
    closeReason = (reason as JSString?)?.toDart;
  }
}

void main() {
  test(
    'bun websocket adapter emits CloseReceived after a local close once the host closes',
    () async {
      final fakeSocket = _FakeBunSocket();
      final adapter = BunServerWebSocketAdapter(
        createJSInteropWrapper(fakeSocket) as BunServerWebSocketHost,
        protocol: 'chat',
      );

      final eventsExpectation = expectLater(
        adapter.events,
        emitsInOrder([
          isA<ws.CloseReceived>()
              .having((event) => event.code, 'code', 1000)
              .having((event) => event.reason, 'reason', 'bye'),
          emitsDone,
        ]),
      );

      await adapter.close(1000, 'bye');
      adapter.closeFromHost(1000, 'bye');

      await eventsExpectation;
    },
  );
}
