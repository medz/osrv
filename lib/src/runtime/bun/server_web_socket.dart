// ignore_for_file: public_member_api_docs

@JS()
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web_socket/web_socket.dart' as ws;

import 'interop.dart';

final class BunServerWebSocketAdapter implements ws.WebSocket {
  BunServerWebSocketAdapter(this._socket, {required String protocol})
    : _protocol = protocol;

  final BunServerWebSocketHost _socket;
  final String _protocol;
  final _events = StreamController<ws.WebSocketEvent>();
  bool _closed = false;

  @override
  void sendText(String s) {
    if (_closed || _events.isClosed) {
      throw ws.WebSocketConnectionClosed();
    }

    bunServerWebSocketSendText(_socket, s);
  }

  @override
  void sendBytes(Uint8List b) {
    if (_closed || _events.isClosed) {
      throw ws.WebSocketConnectionClosed();
    }

    bunServerWebSocketSendBytes(_socket, b);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_closed || _events.isClosed) {
      throw ws.WebSocketConnectionClosed();
    }

    bunServerWebSocketClose(_socket, code: code, reason: reason);
    _closed = true;
  }

  @override
  Stream<ws.WebSocketEvent> get events => _events.stream;

  @override
  String get protocol => _protocol;

  void addMessage(JSAny message) {
    if (_events.isClosed) {
      return;
    }

    final event = _webSocketEventFromBunMessage(message);
    if (event != null) {
      _events.add(event);
    }
  }

  void closeFromHost(int? code, String? reason) {
    if (_events.isClosed) {
      return;
    }

    _closed = true;
    _events.add(ws.CloseReceived(code, reason ?? ''));
    unawaited(_events.close());
  }
}

ws.WebSocketEvent? _webSocketEventFromBunMessage(JSAny message) {
  if (message.isA<JSString>()) {
    return ws.TextDataReceived((message as JSString).toDart);
  }

  if (message.isA<JSUint8Array>()) {
    return ws.BinaryDataReceived((message as JSUint8Array).toDart);
  }

  if (message.isA<JSArrayBuffer>()) {
    return ws.BinaryDataReceived(
      (message as JSArrayBuffer).toDart.asUint8List(),
    );
  }

  final dartValue = message.dartify();
  return switch (dartValue) {
    Uint8List() => ws.BinaryDataReceived(dartValue),
    ByteBuffer() => ws.BinaryDataReceived(dartValue.asUint8List()),
    List<int>() => ws.BinaryDataReceived(Uint8List.fromList(dartValue)),
    String() => ws.TextDataReceived(dartValue),
    _ => ws.BinaryDataReceived(
      Uint8List.fromList(utf8.encode(dartValue.toString())),
    ),
  };
}
