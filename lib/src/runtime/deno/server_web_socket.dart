// ignore_for_file: public_member_api_docs

@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:web_socket/web_socket.dart' as ws;

final class DenoServerWebSocketAdapter implements ws.WebSocket {
  DenoServerWebSocketAdapter(this._socket)
    : _protocol = _socket.protocol,
      _closedCompleter = Completer<void>(),
      _openedCompleter = Completer<void>() {
    _socket.binaryType = 'arraybuffer';

    if (_socket.readyState == web.WebSocket.OPEN) {
      _openedCompleter.complete();
    } else {
      unawaited(
        _socket.onOpen.first.then((_) {
          if (!_openedCompleter.isCompleted) {
            _openedCompleter.complete();
          }
        }),
      );
    }

    _socket.onMessage.listen((event) {
      if (_events.isClosed || event.data == null) {
        return;
      }

      final data = event.data!;
      if (data.typeofEquals('string')) {
        _events.add(ws.TextDataReceived((data as JSString).toDart));
        return;
      }

      if (data.typeofEquals('object') &&
          (data as JSObject).instanceOfString('ArrayBuffer')) {
        _events.add(
          ws.BinaryDataReceived((data as JSArrayBuffer).toDart.asUint8List()),
        );
      }
    });

    unawaited(
      _socket.onClose.first.then((event) {
        closeFromHost(event.code, event.reason);
      }),
    );

    unawaited(
      _socket.onError.first.then((_) {
        closeFromHost(1006, 'error');
      }),
    );
  }

  final web.WebSocket _socket;
  final String _protocol;
  final Completer<void> _closedCompleter;
  final Completer<void> _openedCompleter;
  final _events = StreamController<ws.WebSocketEvent>();
  bool _closed = false;

  @override
  void sendText(String s) {
    if (_closed || _events.isClosed) {
      throw ws.WebSocketConnectionClosed();
    }

    _socket.send(s.toJS);
  }

  @override
  void sendBytes(Uint8List b) {
    if (_closed || _events.isClosed) {
      throw ws.WebSocketConnectionClosed();
    }

    _socket.send(b.toJS);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_closed || _events.isClosed) {
      throw ws.WebSocketConnectionClosed();
    }

    _closed = true;

    if (code != null && reason != null) {
      _socket.close(code, reason);
    } else if (code != null) {
      _socket.close(code);
    } else {
      _socket.close();
    }

    await closed;
  }

  @override
  Stream<ws.WebSocketEvent> get events => _events.stream;

  @override
  String get protocol => _protocol;

  Future<void> get closed => _closedCompleter.future;
  Future<void> get opened => _openedCompleter.future;

  void closeFromHost(int? code, String? reason) {
    if (_events.isClosed) {
      if (!_openedCompleter.isCompleted) {
        _openedCompleter.complete();
      }
      _completeClosed();
      return;
    }

    _closed = true;
    _events.add(ws.CloseReceived(code, reason ?? ''));
    unawaited(_events.close());
    if (!_openedCompleter.isCompleted) {
      _openedCompleter.complete();
    }
    _completeClosed();
  }

  void _completeClosed() {
    if (!_closedCompleter.isCompleted) {
      _closedCompleter.complete();
    }
  }
}
