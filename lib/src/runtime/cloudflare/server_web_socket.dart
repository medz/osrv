// ignore_for_file: public_member_api_docs

@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web_socket/web_socket.dart' as ws;

import 'host.dart';

final class CloudflareServerWebSocketAdapter implements ws.WebSocket {
  CloudflareServerWebSocketAdapter(this._socket, {required String protocol})
    : _protocol = protocol {
    cloudflareWebSocketAddEventListener(
      _socket,
      'message',
      ((JSAny? event) {
        if (_events.isClosed || event == null) {
          return;
        }

        final data = (event as JSObject).getProperty<JSAny?>('data'.toJS);
        if (data == null) {
          return;
        }

        if (data.typeofEquals('string')) {
          _events.add(ws.TextDataReceived((data as JSString).toDart));
          return;
        }

        final dartValue = data.dartify();
        switch (dartValue) {
          case Uint8List():
            _events.add(ws.BinaryDataReceived(dartValue));
            break;
          case ByteBuffer():
            _events.add(ws.BinaryDataReceived(dartValue.asUint8List()));
            break;
          case List<int>():
            _events.add(ws.BinaryDataReceived(Uint8List.fromList(dartValue)));
            break;
          case String():
            _events.add(ws.TextDataReceived(dartValue));
            break;
          default:
            break;
        }
      }).toJS,
    );

    cloudflareWebSocketAddEventListener(
      _socket,
      'close',
      ((JSAny? event) {
        if (_events.isClosed) {
          return;
        }

        final object = event as JSObject?;
        final code = object?.getProperty<JSNumber?>('code'.toJS)?.toDartInt;
        final reason = object?.getProperty<JSString?>('reason'.toJS)?.toDart;
        _events.add(ws.CloseReceived(code, reason ?? ''));
        unawaited(_events.close());
      }).toJS,
    );

    cloudflareWebSocketAddEventListener(
      _socket,
      'error',
      ((JSAny? _) {
        if (_events.isClosed) {
          return;
        }

        _events.add(ws.CloseReceived(1006, 'error'));
        unawaited(_events.close());
      }).toJS,
    );
  }

  final CloudflareWebSocketHost _socket;
  final String _protocol;
  final _events = StreamController<ws.WebSocketEvent>();

  @override
  void sendText(String s) {
    if (_events.isClosed) {
      throw ws.WebSocketConnectionClosed();
    }

    cloudflareWebSocketSendText(_socket, s);
  }

  @override
  void sendBytes(Uint8List b) {
    if (_events.isClosed) {
      throw ws.WebSocketConnectionClosed();
    }

    cloudflareWebSocketSendBytes(_socket, b);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_events.isClosed) {
      throw ws.WebSocketConnectionClosed();
    }

    unawaited(_events.close());
    cloudflareWebSocketClose(_socket, code: code, reason: reason);
  }

  @override
  Stream<ws.WebSocketEvent> get events => _events.stream;

  @override
  String get protocol => _protocol;
}
