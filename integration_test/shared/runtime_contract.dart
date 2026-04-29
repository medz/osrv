import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:web_socket/web_socket.dart' as ws;

import 'test_support.dart';

Future<void> expectHelloEndpoint(
  Uri baseUri, {
  required String expectedBody,
  required String expectedRuntimeHeader,
}) async {
  final response = await send(
    baseUri.resolve('/hello'),
    headers: {'accept': 'text/plain'},
  );
  expect(response.statusCode, 200);
  expect(await response.transform(utf8.decoder).join(), expectedBody);
  expect(response.headers.value('x-runtime'), expectedRuntimeHeader);
}

Future<void> expectWebSocketEcho(
  Uri baseUri, {
  String path = '/chat',
  String protocol = 'chat',
  List<String>? requestedProtocols,
  String connectedMessage = 'connected',
  String outboundMessage = 'ping',
  String echoedMessage = 'echo:ping',
  int expectedCloseCode = 1000,
}) async {
  final webSocket = await WebSocket.connect(
    baseUri
        .replace(scheme: 'ws', path: path, query: '', fragment: '')
        .toString(),
    protocols: requestedProtocols ?? [protocol],
  );
  addTearDown(() async {
    if (webSocket.closeCode == null) {
      await webSocket.close();
    }
  });

  final events = StreamIterator<Object?>(webSocket);
  expect(webSocket.protocol, protocol);
  expect(await events.moveNext().timeout(const Duration(seconds: 5)), isTrue);
  expect(events.current, connectedMessage);

  webSocket.add(outboundMessage);
  expect(await events.moveNext().timeout(const Duration(seconds: 5)), isTrue);
  expect(events.current, echoedMessage);

  await webSocket.close(1000, 'client done');
  expect(
    await events.moveNext().timeout(
      const Duration(seconds: 5),
      onTimeout: () => true,
    ),
    isFalse,
    reason: 'WebSocket stream should finish after the close handshake.',
  );
  expect(
    webSocket.closeCode,
    expectedCloseCode,
    reason: 'WebSocket close handshake should complete cleanly.',
  );
}

Future<void> expectWebSocketProtocolErrorTeardown(
  Uri baseUri, {
  String path = '/chat',
  List<String> protocols = const ['chat'],
  String connectedMessage = 'connected',
  Set<int?> expectedCloseCodes = const {1007},
}) async {
  final client = await _ContractRawWebSocketClient.connect(
    baseUri.replace(scheme: 'ws', path: path, query: '', fragment: ''),
    protocols: protocols,
  );
  addTearDown(client.dispose);

  final connected = await client.nextFrame(timeout: const Duration(seconds: 5));
  expect(connected.opcode, 0x1);
  expect(utf8.decode(connected.payload), connectedMessage);

  await client.sendFrame(opcode: 0x1, payload: const [0xC3, 0x28]);

  int? observedCloseCode;
  try {
    final close = await client.nextFrame(timeout: const Duration(seconds: 5));
    expect(close.opcode, 0x8);
    observedCloseCode = _decodeClosePayload(close.payload).code;
  } on StateError {
    observedCloseCode = null;
  }
  expect(
    expectedCloseCodes,
    contains(observedCloseCode),
    reason: 'Unexpected protocol-error close code.',
  );

  await client.done.timeout(const Duration(seconds: 5));
}

Future<void> expectObservableLocalClose({
  required Stream<ws.WebSocketEvent> events,
  required Future<void> Function() startLocalClose,
  required FutureOr<void> Function() triggerTerminalClose,
  required int expectedCode,
  required String expectedReason,
}) async {
  final eventsExpectation = expectLater(
    events,
    emitsInOrder([
      isA<ws.CloseReceived>()
          .having((event) => event.code, 'code', expectedCode)
          .having((event) => event.reason, 'reason', expectedReason),
      emitsDone,
    ]),
  );

  final closeFuture = startLocalClose();
  await triggerTerminalClose();

  await closeFuture;
  await eventsExpectation;
}

final class _ContractRawWebSocketClient {
  _ContractRawWebSocketClient._(this._socket) {
    _subscription = _socket.listen(
      _onData,
      onDone: _onDone,
      onError: _onError,
      cancelOnError: true,
    );
  }

  static Future<_ContractRawWebSocketClient> connect(
    Uri uri, {
    List<String> protocols = const <String>[],
  }) async {
    final socket = await Socket.connect(uri.host, uri.port);
    final client = _ContractRawWebSocketClient._(socket);

    final path = uri.path.isEmpty ? '/' : uri.path;
    final target = uri.hasQuery ? '$path?${uri.query}' : path;
    final key = base64.encode(List<int>.generate(16, (index) => index + 1));
    final request = StringBuffer()
      ..write('GET $target HTTP/1.1\r\n')
      ..write('Host: ${uri.host}:${uri.port}\r\n')
      ..write('Upgrade: websocket\r\n')
      ..write('Connection: Upgrade\r\n')
      ..write('Sec-WebSocket-Version: 13\r\n')
      ..write('Sec-WebSocket-Key: $key\r\n');
    if (protocols.isNotEmpty) {
      request.write('Sec-WebSocket-Protocol: ${protocols.join(', ')}\r\n');
    }
    request.write('\r\n');

    socket.add(utf8.encode(request.toString()));
    await socket.flush();

    final response = await client._handshake.future.timeout(
      const Duration(seconds: 5),
    );
    expect(response.statusCode, 101);
    return client;
  }

  final Socket _socket;
  final _buffer = BytesBuilder(copy: false);
  final _frames = <_ContractServerFrame>[];
  final _pendingFrames = <Completer<_ContractServerFrame>>[];
  final _handshake = Completer<_ContractHandshakeResponse>();
  final _doneCompleter = Completer<void>();
  late final StreamSubscription<List<int>> _subscription;
  bool _handshakeComplete = false;

  Future<void> get done => _doneCompleter.future;

  Future<void> sendFrame({
    required int opcode,
    required List<int> payload,
    bool fin = true,
  }) async {
    _socket.add(_encodeClientFrame(opcode: opcode, payload: payload, fin: fin));
    await _socket.flush();
  }

  Future<_ContractServerFrame> nextFrame({Duration? timeout}) {
    final queued = _takeFrame();
    if (queued != null) {
      return Future<_ContractServerFrame>.value(queued);
    }

    final completer = Completer<_ContractServerFrame>();
    _pendingFrames.add(completer);
    final future = completer.future;
    return timeout == null ? future : future.timeout(timeout);
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _socket.close();
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  void _onData(List<int> chunk) {
    if (chunk.isEmpty) {
      return;
    }

    _buffer.add(chunk);
    final bytes = _buffer.takeBytes();
    final offset = _handshakeComplete
        ? _parseFrames(bytes)
        : _parseHandshakeAndFrames(bytes);
    if (offset < bytes.length) {
      _buffer.add(bytes.sublist(offset));
    }
  }

  int _parseHandshakeAndFrames(Uint8List bytes) {
    final headerEnd = _findHttpHeaderEnd(bytes);
    if (headerEnd == null) {
      return 0;
    }

    final responseText = ascii.decode(bytes.sublist(0, headerEnd));
    final lines = responseText.split('\r\n');
    final statusLine = lines.first.split(' ');
    final statusCode = int.parse(statusLine[1]);

    _handshakeComplete = true;
    if (!_handshake.isCompleted) {
      _handshake.complete(_ContractHandshakeResponse(statusCode));
    }

    return _parseFrames(bytes, start: headerEnd + 4);
  }

  int _parseFrames(Uint8List bytes, {int start = 0}) {
    var offset = start;
    while (true) {
      final frame = _tryParseServerFrame(bytes, offset);
      if (frame == null) {
        break;
      }
      offset = frame.nextOffset;
      _queueFrame(_ContractServerFrame(frame.opcode, frame.payload, frame.fin));
    }
    return offset;
  }

  void _queueFrame(_ContractServerFrame frame) {
    if (_pendingFrames.isNotEmpty) {
      _pendingFrames.removeAt(0).complete(frame);
      return;
    }
    _frames.add(frame);
  }

  _ContractServerFrame? _takeFrame() {
    if (_frames.isEmpty) {
      return null;
    }
    return _frames.removeAt(0);
  }

  void _onDone() {
    while (_pendingFrames.isNotEmpty) {
      _pendingFrames
          .removeAt(0)
          .completeError(
            StateError('WebSocket closed before the next frame arrived.'),
          );
    }
    if (!_handshake.isCompleted) {
      _handshake.completeError(
        StateError('Socket closed before the websocket handshake completed.'),
      );
    }
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    while (_pendingFrames.isNotEmpty) {
      _pendingFrames.removeAt(0).completeError(error, stackTrace);
    }
    if (!_handshake.isCompleted) {
      _handshake.completeError(error, stackTrace);
    }
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.completeError(error, stackTrace);
    }
  }
}

final class _ContractHandshakeResponse {
  const _ContractHandshakeResponse(this.statusCode);

  final int statusCode;
}

final class _ContractServerFrame {
  const _ContractServerFrame(this.opcode, this.payload, this.fin);

  final int opcode;
  final Uint8List payload;
  final bool fin;
}

final class _ContractParsedServerFrame {
  const _ContractParsedServerFrame({
    required this.fin,
    required this.opcode,
    required this.payload,
    required this.nextOffset,
  });

  final bool fin;
  final int opcode;
  final Uint8List payload;
  final int nextOffset;
}

int? _findHttpHeaderEnd(Uint8List bytes) {
  for (var i = 0; i <= bytes.length - 4; i++) {
    if (bytes[i] == 13 &&
        bytes[i + 1] == 10 &&
        bytes[i + 2] == 13 &&
        bytes[i + 3] == 10) {
      return i;
    }
  }
  return null;
}

_ContractParsedServerFrame? _tryParseServerFrame(Uint8List bytes, int offset) {
  if (bytes.length - offset < 2) {
    return null;
  }

  final first = bytes[offset];
  final second = bytes[offset + 1];
  final fin = (first & 0x80) != 0;
  final masked = (second & 0x80) != 0;
  if (masked) {
    throw StateError('Server websocket frames must not be masked.');
  }

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

  if (bytes.length - cursor < payloadLength) {
    return null;
  }

  return _ContractParsedServerFrame(
    fin: fin,
    opcode: first & 0x0F,
    payload: Uint8List.sublistView(bytes, cursor, cursor + payloadLength),
    nextOffset: cursor + payloadLength,
  );
}

Uint8List _encodeClientFrame({
  required int opcode,
  required List<int> payload,
  required bool fin,
}) {
  final mask = Uint8List.fromList(const [1, 2, 3, 4]);
  final header = BytesBuilder(copy: false);
  header.addByte((fin ? 0x80 : 0x00) | (opcode & 0x0F));
  if (payload.length < 126) {
    header.addByte(0x80 | payload.length);
  } else if (payload.length <= 0xFFFF) {
    header
      ..addByte(0x80 | 126)
      ..addByte((payload.length >> 8) & 0xFF)
      ..addByte(payload.length & 0xFF);
  } else {
    header.addByte(0x80 | 127);
    final length = payload.length;
    for (var shift = 56; shift >= 0; shift -= 8) {
      header.addByte((length >> shift) & 0xFF);
    }
  }
  header.add(mask);

  final masked = Uint8List.fromList(payload);
  for (var i = 0; i < masked.length; i++) {
    masked[i] ^= mask[i % mask.length];
  }
  header.add(masked);
  return header.takeBytes();
}

({int? code, String reason}) _decodeClosePayload(Uint8List payload) {
  if (payload.length < 2) {
    return (code: null, reason: '');
  }

  final code = (payload[0] << 8) | payload[1];
  final reason = payload.length > 2 ? utf8.decode(payload.sublist(2)) : '';
  return (code: code, reason: reason);
}
