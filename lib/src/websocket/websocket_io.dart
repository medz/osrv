import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ht/ht.dart' show Response;

import '../request.dart';
import '../types.dart';
import '../websocket_contract.dart';

Future<ServerWebSocket> upgradeWebSocket(
  ServerRequest request, {
  WebSocketLimits limits = const WebSocketLimits(),
}) async {
  final runtimeRequest = request.runtime?.raw.dartRequest;
  if (runtimeRequest is! HttpRequest) {
    throw UnsupportedError(
      'Request runtime does not expose dart:io HttpRequest for websocket upgrade.',
    );
  }

  if (request.isWebSocketUpgraded) {
    throw StateError('Request has already been upgraded to websocket.');
  }

  final socket = await WebSocketTransformer.upgrade(runtimeRequest);
  if (limits.idleTimeout > Duration.zero) {
    final pingMs = math.max(1000, limits.idleTimeout.inMilliseconds ~/ 2);
    socket.pingInterval = Duration(milliseconds: pingMs);
  }

  request.markWebSocketUpgraded();
  request.setRawWebSocket(socket);
  return _IoServerWebSocket(socket, limits);
}

final class _IoServerWebSocket implements ServerWebSocket {
  _IoServerWebSocket(this._socket, this._limits) {
    _socket.done.whenComplete(() {
      _isOpen = false;
    });
  }

  final WebSocket _socket;
  final WebSocketLimits _limits;
  bool _isOpen = true;

  @override
  Stream<Object> get messages {
    return _socket.map((event) {
      _validateFrame(event);
      return event;
    });
  }

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> sendBytes(List<int> data) async {
    _assertOpen();
    _validateFrame(data);
    _socket.add(data);
  }

  @override
  Future<void> sendText(String data) async {
    _assertOpen();
    _validateFrame(data);
    _socket.add(data);
  }

  @override
  Future<void> close({int? code, String? reason}) async {
    if (!_isOpen) {
      return;
    }

    _isOpen = false;
    await _socket.close(code, reason);
  }

  @override
  Future<void> done() => _socket.done;

  @override
  Response toResponse() => Response.empty(status: 101);

  void _assertOpen() {
    if (!_isOpen) {
      throw StateError('WebSocket is closed.');
    }
  }

  void _validateFrame(Object event) {
    final size = switch (event) {
      final String value => utf8.encode(value).length,
      final List<int> value => value.length,
      _ => 0,
    };

    if (size > _limits.maxFrameBytes) {
      unawaited(
        _socket.close(WebSocketStatus.messageTooBig, 'Frame too large'),
      );
      throw StateError(
        'WebSocket frame exceeds maxFrameBytes (${_limits.maxFrameBytes}).',
      );
    }
  }
}
