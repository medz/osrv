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
            throw UnsupportedError(
              'Unsupported Cloudflare websocket payload type: ${dartValue.runtimeType}',
            );
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
        _closed = true;
        if (!_closeSent) {
          _closeSent = true;
          _replyToPeerClose(code, reason);
        }
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

        _closed = true;
        _events.add(ws.CloseReceived(1006, 'error'));
        unawaited(_events.close());
      }).toJS,
    );
  }

  final CloudflareWebSocketHost _socket;
  final String _protocol;
  final _events = StreamController<ws.WebSocketEvent>();
  bool _closeSent = false;
  bool _closed = false;

  @override
  void sendText(String s) {
    if (_closed || _events.isClosed) {
      throw ws.WebSocketConnectionClosed();
    }

    cloudflareWebSocketSendText(_socket, s);
  }

  @override
  void sendBytes(Uint8List b) {
    if (_closed || _events.isClosed) {
      throw ws.WebSocketConnectionClosed();
    }

    cloudflareWebSocketSendBytes(_socket, b);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_closed || _events.isClosed) {
      throw ws.WebSocketConnectionClosed();
    }

    cloudflareWebSocketClose(_socket, code: code, reason: reason);
    _closeSent = true;
    _closed = true;
  }

  @override
  Stream<ws.WebSocketEvent> get events => _events.stream;

  @override
  String get protocol => _protocol;

  void _replyToPeerClose(int? code, String? reason) {
    try {
      final replyCode = _normalizeReplyCloseCode(code);

      cloudflareWebSocketClose(
        _socket,
        code: replyCode,
        reason: reason == null || reason.isEmpty ? null : reason,
      );
    } catch (_) {
      // Ignore teardown failures while acknowledging a peer-initiated close.
    }
  }
}

int _normalizeReplyCloseCode(int? code) {
  if (code == null) {
    return 1000;
  }

  if (code == 1000) {
    return code;
  }

  if (code >= 1001 && code <= 1014) {
    if (code == 1004 || code == 1005 || code == 1006) {
      return 1000;
    }

    return code;
  }

  if (code >= 3000 && code <= 4999) {
    return code;
  }

  return 1000;
}
