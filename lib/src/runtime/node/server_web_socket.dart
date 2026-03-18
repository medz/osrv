// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket/web_socket.dart' as ws;

import 'http_host.dart';

final class NodeServerWebSocketAdapter implements ws.WebSocket {
  NodeServerWebSocketAdapter({
    required NodeSocketHost socket,
    required Stream<List<int>> incoming,
    required String protocol,
  }) : _socket = socket,
       _protocol = protocol {
    _subscription = incoming.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: true,
    );
  }

  final NodeSocketHost _socket;
  final String _protocol;
  final _events = StreamController<ws.WebSocketEvent>();
  final _closedCompleter = Completer<void>();
  late final StreamSubscription<List<int>> _subscription;
  final _buffer = BytesBuilder(copy: false);
  final _fragmentBuffer = BytesBuilder(copy: false);
  bool _closed = false;
  bool _closeReceived = false;
  int? _fragmentOpcode;

  @override
  void sendText(String s) {
    _ensureOpen();
    unawaited(
      nodeSocketWrite(
        _socket,
        _encodeFrame(opcode: 0x1, payload: utf8.encode(s)),
      ),
    );
  }

  @override
  void sendBytes(Uint8List b) {
    _ensureOpen();
    unawaited(nodeSocketWrite(_socket, _encodeFrame(opcode: 0x2, payload: b)));
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    _ensureOpen();

    final payload = _closePayload(code, reason);
    _closed = true;
    Object? pendingError;
    StackTrace? pendingStackTrace;
    try {
      await nodeSocketWrite(
        _socket,
        _encodeFrame(opcode: 0x8, payload: payload),
      );
      unawaited(nodeSocketEnd(_socket));
    } catch (error, stackTrace) {
      pendingError = error;
      pendingStackTrace = stackTrace;
    } finally {
      if (!_events.isClosed) {
        await _events.close();
      }
      _completeClosed();
    }

    if (pendingError != null && pendingStackTrace != null) {
      Error.throwWithStackTrace(pendingError, pendingStackTrace);
    }
  }

  @override
  Stream<ws.WebSocketEvent> get events => _events.stream;

  @override
  String get protocol => _protocol;

  Future<void> get closed => _closedCompleter.future;

  Future<void> dispose([int? code, String? reason]) async {
    if (_closed) {
      return;
    }

    _closed = true;
    await _subscription.cancel();
    if (!_events.isClosed) {
      if (!_closeReceived) {
        _events.add(ws.CloseReceived(code, reason ?? ''));
      }
      await _events.close();
    }
    _completeClosed();
  }

  void _ensureOpen() {
    if (_closed || _events.isClosed) {
      throw ws.WebSocketConnectionClosed();
    }
  }

  void _onData(List<int> chunk) {
    if (_closed || chunk.isEmpty) {
      return;
    }

    _buffer.add(chunk);
    final bytes = _buffer.takeBytes();
    var offset = 0;

    while (true) {
      final frame = _tryParseFrame(bytes, offset);
      if (frame == null) {
        break;
      }

      offset = frame.nextOffset;
      if (!_handleFrame(frame)) {
        return;
      }

      if (_closed) {
        break;
      }
    }

    if (offset < bytes.length) {
      _buffer.add(bytes.sublist(offset));
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (_closed) {
      return;
    }

    _closed = true;
    _events.add(ws.CloseReceived(1006, error.toString()));
    unawaited(_events.close());
    _completeClosed();
    Zone.current.handleUncaughtError(error, stackTrace);
  }

  void _onDone() {
    if (_events.isClosed) {
      _completeClosed();
      return;
    }

    if (!_closeReceived) {
      _events.add(ws.CloseReceived(1006, ''));
    }
    _closed = true;
    unawaited(_events.close());
    _completeClosed();
  }

  void _completeClosed() {
    if (!_closedCompleter.isCompleted) {
      _closedCompleter.complete();
    }
  }

  bool _handleFrame(_ParsedFrame frame) {
    if (frame.rsvBits != 0) {
      _protocolError('RSV bits are unsupported.');
      return false;
    }

    if (!frame.masked) {
      _protocolError('Client websocket frames must be masked.');
      return false;
    }

    if (_isControlOpcode(frame.opcode) && !frame.fin) {
      _protocolError('Control frames must not be fragmented.');
      return false;
    }

    if (_isControlOpcode(frame.opcode) && frame.payload.length > 125) {
      _protocolError('Control frame payload is too large.');
      return false;
    }

    switch (frame.opcode) {
      case 0x0:
        return _handleContinuationFrame(frame);
      case 0x1:
        return _handleDataFrame(frame, opcode: 0x1);
      case 0x2:
        return _handleDataFrame(frame, opcode: 0x2);
      case 0x8:
        if (frame.payload.length == 1) {
          _protocolError('Close frames must not use a 1-byte payload.');
          return false;
        }

        final close = _decodeClose(frame.payload);
        _closeReceived = true;
        _events.add(ws.CloseReceived(close.code, close.reason));
        unawaited(nodeSocketEnd(_socket));
        unawaited(_events.close());
        _closed = true;
        _completeClosed();
        return true;
      case 0x9:
        unawaited(
          nodeSocketWrite(
            _socket,
            _encodeFrame(opcode: 0xA, payload: frame.payload),
          ),
        );
        return true;
      case 0xA:
        return true;
      default:
        _protocolError('Unsupported websocket opcode.');
        return false;
    }
  }

  bool _handleDataFrame(_ParsedFrame frame, {required int opcode}) {
    if (_fragmentOpcode != null) {
      _protocolError('Received a new data frame before finishing a fragment.');
      return false;
    }

    if (frame.fin) {
      return _emitMessage(opcode, frame.payload);
    }

    _fragmentOpcode = opcode;
    _fragmentBuffer.add(frame.payload);
    return true;
  }

  bool _handleContinuationFrame(_ParsedFrame frame) {
    final opcode = _fragmentOpcode;
    if (opcode == null) {
      _protocolError('Unexpected continuation frame.');
      return false;
    }

    _fragmentBuffer.add(frame.payload);
    if (!frame.fin) {
      return true;
    }

    final payload = _fragmentBuffer.takeBytes();
    _fragmentOpcode = null;
    return _emitMessage(opcode, payload);
  }

  bool _emitMessage(int opcode, Uint8List payload) {
    switch (opcode) {
      case 0x1:
        try {
          _events.add(ws.TextDataReceived(utf8.decode(payload)));
          return true;
        } on FormatException {
          _protocolError('Invalid UTF-8 payload.');
          return false;
        }
      case 0x2:
        _events.add(ws.BinaryDataReceived(payload));
        return true;
      default:
        _protocolError('Unsupported websocket opcode.');
        return false;
    }
  }

  void _protocolError(String reason) {
    nodeSocketDestroy(_socket);
    unawaited(dispose(1002, reason));
  }
}

Uint8List _encodeFrame({required int opcode, required List<int> payload}) {
  final header = BytesBuilder(copy: false);
  header.addByte(0x80 | (opcode & 0x0F));

  if (payload.length < 126) {
    header.addByte(payload.length);
  } else if (payload.length <= 0xFFFF) {
    header
      ..addByte(126)
      ..addByte((payload.length >> 8) & 0xFF)
      ..addByte(payload.length & 0xFF);
  } else {
    header.addByte(127);
    final length = payload.length;
    for (var shift = 56; shift >= 0; shift -= 8) {
      header.addByte((length >> shift) & 0xFF);
    }
  }

  header.add(payload);
  return header.takeBytes();
}

Uint8List _closePayload(int? code, String? reason) {
  if (code == null && (reason == null || reason.isEmpty)) {
    return Uint8List(0);
  }

  final builder = BytesBuilder(copy: false);
  if (code != null) {
    builder
      ..addByte((code >> 8) & 0xFF)
      ..addByte(code & 0xFF);
  }
  if (reason != null && reason.isNotEmpty) {
    builder.add(utf8.encode(reason));
  }
  return builder.takeBytes();
}

_ParsedFrame? _tryParseFrame(Uint8List bytes, int offset) {
  if (bytes.length - offset < 2) {
    return null;
  }

  final first = bytes[offset];
  final second = bytes[offset + 1];
  final fin = (first & 0x80) != 0;
  final rsvBits = (first >> 4) & 0x07;
  final masked = (second & 0x80) != 0;
  var payloadLength = second & 0x7F;
  var cursor = offset + 2;

  if (payloadLength == 126) {
    if (bytes.length - cursor < 2) {
      return null;
    }
    payloadLength = (bytes[cursor] << 8) | bytes[cursor + 1];
    cursor += 2;
  } else if (payloadLength == 127) {
    if (bytes.length - cursor < 8) {
      return null;
    }
    payloadLength = 0;
    for (var i = 0; i < 8; i++) {
      payloadLength = (payloadLength << 8) | bytes[cursor + i];
    }
    cursor += 8;
  }

  Uint8List? mask;
  if (masked) {
    if (bytes.length - cursor < 4) {
      return null;
    }
    mask = Uint8List.sublistView(bytes, cursor, cursor + 4);
    cursor += 4;
  }

  if (bytes.length - cursor < payloadLength) {
    return null;
  }

  final payload = Uint8List.sublistView(bytes, cursor, cursor + payloadLength);
  final decoded = Uint8List.fromList(payload);
  if (mask != null) {
    for (var i = 0; i < decoded.length; i++) {
      decoded[i] ^= mask[i % 4];
    }
  }

  return _ParsedFrame(
    fin: fin,
    masked: masked,
    opcode: first & 0x0F,
    payload: decoded,
    rsvBits: rsvBits,
    nextOffset: cursor + payloadLength,
  );
}

({int? code, String reason}) _decodeClose(Uint8List payload) {
  if (payload.length < 2) {
    return (code: null, reason: '');
  }

  final code = (payload[0] << 8) | payload[1];
  final reason = payload.length > 2 ? utf8.decode(payload.sublist(2)) : '';
  return (code: code, reason: reason);
}

final class _ParsedFrame {
  const _ParsedFrame({
    required this.fin,
    required this.masked,
    required this.opcode,
    required this.payload,
    required this.rsvBits,
    required this.nextOffset,
  });

  final bool fin;
  final bool masked;
  final int opcode;
  final Uint8List payload;
  final int rsvBits;
  final int nextOffset;
}

bool _isControlOpcode(int opcode) => opcode >= 0x8;
