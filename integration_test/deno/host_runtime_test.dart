@TestOn('node')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:osrv/src/runtime/deno/server_web_socket.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import '../shared/runtime_contract.dart';

@JSExport()
final class _FakeDenoSocket {
  final Map<String, JSFunction> _listeners = <String, JSFunction>{};

  String protocol = 'chat';
  int readyState = web.WebSocket.OPEN;
  String binaryType = '';
  int? closeCode;
  String? closeReason;

  void addEventListener(String type, JSFunction listener) {
    _listeners[type] = listener;
  }

  void removeEventListener(String type, JSFunction listener) {
    if (identical(_listeners[type], listener)) {
      _listeners.remove(type);
    }
  }

  void send(JSAny? data) {
    data;
  }

  void close([JSAny? code, JSAny? reason]) {
    closeCode = (code as JSNumber?)?.toDartInt;
    closeReason = (reason as JSString?)?.toDart;
  }

  void emitClose([int? code, String? reason]) {
    final listener = _listeners['close'];
    if (listener == null) {
      return;
    }

    final event = JSObject();
    if (code != null) {
      event.setProperty('code'.toJS, code.toJS);
    }
    if (reason != null) {
      event.setProperty('reason'.toJS, reason.toJS);
    }
    listener.callAsFunction(null, event);
  }
}

void main() {
  test('deno websocket adapter close waits for the host close event', () async {
    final fakeSocket = _FakeDenoSocket();
    final adapter = DenoServerWebSocketAdapter(
      createJSInteropWrapper(fakeSocket) as web.WebSocket,
    );

    final closeFuture = adapter.close(1000, 'bye');

    await expectLater(
      closeFuture.timeout(const Duration(milliseconds: 50)),
      throwsA(isA<TimeoutException>()),
    );

    fakeSocket.emitClose(1000, 'bye');
    await closeFuture.timeout(const Duration(milliseconds: 250));
  });

  test(
    'deno websocket adapter emits CloseReceived after a local close once the host closes',
    () async {
      final fakeSocket = _FakeDenoSocket();
      final adapter = DenoServerWebSocketAdapter(
        createJSInteropWrapper(fakeSocket) as web.WebSocket,
      );

      await expectObservableLocalClose(
        events: adapter.events,
        startLocalClose: () => adapter.close(1000, 'bye'),
        triggerTerminalClose: () => fakeSocket.emitClose(1000, 'bye'),
        expectedCode: 1000,
        expectedReason: 'bye',
      );
    },
  );
}
