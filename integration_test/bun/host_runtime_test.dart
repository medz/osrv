@TestOn('node')
library;

import 'dart:js_interop';

import 'package:osrv/src/runtime/bun/interop.dart' show BunServerWebSocketHost;
import 'package:osrv/src/runtime/bun/server_web_socket.dart';
import 'package:test/test.dart';

import '../shared/runtime_contract.dart';

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
  test('bun websocket adapter rejects unsupported host payload types', () {
    final fakeSocket = _FakeBunSocket();
    final adapter = BunServerWebSocketAdapter(
      createJSInteropWrapper(fakeSocket) as BunServerWebSocketHost,
      protocol: 'chat',
    );

    expect(
      () => adapter.addMessage(JSObject()),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test(
    'bun websocket adapter emits CloseReceived after a local close once the host closes',
    () async {
      final fakeSocket = _FakeBunSocket();
      final adapter = BunServerWebSocketAdapter(
        createJSInteropWrapper(fakeSocket) as BunServerWebSocketHost,
        protocol: 'chat',
      );

      await expectObservableLocalClose(
        events: adapter.events,
        startLocalClose: () => adapter.close(1000, 'bye'),
        triggerTerminalClose: () => adapter.closeFromHost(1000, 'bye'),
        expectedCode: 1000,
        expectedReason: 'bye',
      );
      expect(fakeSocket.closeCode, 1000);
      expect(fakeSocket.closeReason, 'bye');
    },
  );
}
