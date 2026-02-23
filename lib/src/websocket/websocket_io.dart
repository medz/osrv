import 'dart:convert';
import 'dart:io';

import 'package:ht/ht.dart' show Response;

import '../request.dart';
import '../websocket/internal.dart';
import '../websocket_contract.dart';

const String _ioRequestContextKey = '__io_http_request';

Future<ServerWebSocket> upgradeWebSocket(ServerRequest request) async {
  final raw = request.context[_ioRequestContextKey];
  if (raw is! HttpRequest) {
    throw UnsupportedError(
      'WebSocket upgrade requires dart:io HttpRequest in request context.',
    );
  }

  final socket = await WebSocketTransformer.upgrade(raw);
  socket.pingInterval = const Duration(seconds: 30);
  return _IoServerWebSocket(socket);
}

final class _IoServerWebSocket implements ServerWebSocket {
  _IoServerWebSocket(this._socket) {
    _socket.done.whenComplete(() {
      _open = false;
    });
  }

  final WebSocket _socket;
  bool _open = true;

  @override
  Stream<Object> get messages => _socket.map((event) {
    if (event is String || event is List<int>) {
      return event;
    }
    return event.toString();
  });

  @override
  bool get isOpen => _open;

  @override
  Future<void> sendText(String data) async {
    _assertOpen();
    _validateFrame(data);
    _socket.add(data);
  }

  @override
  Future<void> sendBytes(List<int> data) async {
    _assertOpen();
    _validateFrame(data);
    _socket.add(data);
  }

  @override
  Future<void> close({int? code, String? reason}) async {
    if (!_open) {
      return;
    }

    _open = false;
    await _socket.close(code, reason);
  }

  @override
  Future<void> done() => _socket.done;

  @override
  Response toResponse() {
    final response = Response.empty(status: 101);
    response.headers.set(websocketUpgradeHeader, websocketUpgradeValue);
    return response;
  }

  void _assertOpen() {
    if (!_open) {
      throw StateError('WebSocket is closed.');
    }
  }

  void _validateFrame(Object event) {
    final size = switch (event) {
      final String value => utf8.encode(value).length,
      final List<int> value => value.length,
      _ => 0,
    };

    if (size > 1024 * 1024) {
      final closeCode = WebSocketStatus.messageTooBig;
      _socket.close(closeCode, 'Frame too large');
      throw StateError('WebSocket frame exceeds 1MB.');
    }

    if (size > 0x7fffffff) {
      throw StateError('WebSocket frame size overflow.');
    }
  }
}
