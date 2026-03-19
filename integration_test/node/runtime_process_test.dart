@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../shared/runtime_contract.dart';
import '../shared/test_support.dart';

void main() {
  test(
    'node runtime websocket server upgrades requests and echoes messages',
    () async {
      if (!await commandAvailable('node')) {
        markTestSkipped('node is not available in the current environment');
        return;
      }

      final process = await _startNodeRuntime();
      attachProcessCleanup(process);

      final stderrBuffer = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
      final lines = stdoutLines(process);

      final uri = await _waitForNodeRuntimeUrl(lines);

      final meta = await send(uri.resolve('/meta'));
      expect(meta.statusCode, 200);
      expect(jsonDecode(await meta.transform(utf8.decoder).join()), {
        'runtime': 'node',
        'kind': 'server',
        'capabilities': {
          'streaming': true,
          'websocket': true,
          'fileSystem': true,
          'backgroundTask': true,
          'rawTcp': true,
          'nodeCompat': true,
        },
        'request': {'hasWebSocket': true, 'upgrade': false},
      });

      final postMeta = await send(
        uri.resolve('/meta'),
        method: 'POST',
        headers: {
          'connection': 'keep-alive, Upgrade',
          'upgrade': 'websocket',
          'sec-websocket-protocol': 'chat, superchat',
        },
      );
      expect(postMeta.statusCode, 200);
      expect(jsonDecode(await postMeta.transform(utf8.decoder).join()), {
        'runtime': 'node',
        'kind': 'server',
        'capabilities': {
          'streaming': true,
          'websocket': true,
          'fileSystem': true,
          'backgroundTask': true,
          'rawTcp': true,
          'nodeCompat': true,
        },
        'request': {'hasWebSocket': true, 'upgrade': false},
      });

      await expectHelloEndpoint(
        uri,
        expectedBody: 'hello from node',
        expectedRuntimeHeader: 'node',
      );
      await expectWebSocketEcho(uri);

      expect(stderrBuffer.toString(), isEmpty);
    },
  );

  test('node runtime close waits for active websocket sessions', () async {
    if (!await commandAvailable('node')) {
      markTestSkipped('node is not available in the current environment');
      return;
    }

    final process = await _startNodeRuntime();
    attachProcessCleanup(process);

    final stderrBuffer = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
    final lines = stdoutLines(process);

    final uri = await _waitForNodeRuntimeUrl(lines);
    final client = await _RawWebSocketClient.connect(
      uri.replace(scheme: 'ws', path: '/chat', query: '', fragment: ''),
      protocols: const ['chat'],
    );

    final connected = await client.nextFrame(
      timeout: const Duration(seconds: 5),
    );
    expect(connected.opcode, 0x1);
    expect(utf8.decode(connected.payload), 'connected');

    final closing = await send(uri.resolve('/close-runtime'));
    expect(closing.statusCode, 200);
    expect(await closing.transform(utf8.decoder).join(), 'closing');

    final close = await client.nextFrame(timeout: const Duration(seconds: 5));
    expect(close.opcode, 0x8);
    expect(_decodeClosePayload(close.payload), (
      code: 1001,
      reason: 'Runtime shutdown',
    ));

    await expectLater(
      process.exitCode.timeout(const Duration(milliseconds: 250)),
      throwsA(isA<TimeoutException>()),
    );

    await client.sendClose(code: 1001, reason: 'Runtime shutdown');
    await client.done.timeout(const Duration(seconds: 5));
    await client.dispose();
    final exitCode = await process.exitCode.timeout(const Duration(seconds: 5));

    expect(exitCode, 0, reason: stderrBuffer.toString());
    expect(stderrBuffer.toString(), isEmpty);
  });

  test(
    'node runtime replies with a close frame when the client initiates close',
    () async {
      if (!await commandAvailable('node')) {
        markTestSkipped('node is not available in the current environment');
        return;
      }

      final process = await _startNodeRuntime();
      attachProcessCleanup(process);

      final stderrBuffer = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
      final uri = await _waitForNodeRuntimeUrl(stdoutLines(process));
      final client = await _RawWebSocketClient.connect(
        uri.replace(scheme: 'ws', path: '/chat', query: '', fragment: ''),
        protocols: const ['chat'],
      );
      addTearDown(client.dispose);

      final connected = await client.nextFrame(
        timeout: const Duration(seconds: 5),
      );
      expect(connected.opcode, 0x1);
      expect(utf8.decode(connected.payload), 'connected');

      await client.sendClose(code: 1000, reason: 'bye');

      final close = await client.nextFrame(timeout: const Duration(seconds: 5));
      expect(close.opcode, 0x8);
      expect(_decodeClosePayload(close.payload), (code: 1000, reason: 'bye'));

      await client.done.timeout(const Duration(seconds: 5));
      expect(stderrBuffer.toString(), isEmpty);
    },
  );

  test(
    'node runtime sends 1009 close when fragmented messages exceed the buffer limit',
    () async {
      if (!await commandAvailable('node')) {
        markTestSkipped('node is not available in the current environment');
        return;
      }

      final process = await _startNodeRuntime();
      attachProcessCleanup(process);

      final stderrBuffer = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
      final uri = await _waitForNodeRuntimeUrl(stdoutLines(process));
      final client = await _RawWebSocketClient.connect(
        uri.replace(scheme: 'ws', path: '/chat', query: '', fragment: ''),
        protocols: const ['chat'],
      );
      addTearDown(client.dispose);

      final connected = await client.nextFrame(
        timeout: const Duration(seconds: 5),
      );
      expect(connected.opcode, 0x1);
      expect(utf8.decode(connected.payload), 'connected');

      final chunk = Uint8List(256 * 1024);
      chunk.fillRange(0, chunk.length, 0x61);

      await client.sendFrame(opcode: 0x1, payload: chunk, fin: false);
      await client.sendFrame(opcode: 0x0, payload: chunk, fin: false);
      await client.sendFrame(opcode: 0x0, payload: chunk, fin: false);
      await client.sendFrame(opcode: 0x0, payload: chunk, fin: false);
      await client.sendFrame(opcode: 0x0, payload: chunk, fin: false);

      final close = await client.nextFrame(timeout: const Duration(seconds: 5));
      expect(close.opcode, 0x8);
      expect(_decodeClosePayload(close.payload).code, 1009);

      await client.done.timeout(const Duration(seconds: 5));
      expect(stderrBuffer.toString(), isEmpty);
    },
  );

  test('node runtime sends 1007 close for invalid UTF-8 text frames', () async {
    if (!await commandAvailable('node')) {
      markTestSkipped('node is not available in the current environment');
      return;
    }

    final process = await _startNodeRuntime();
    attachProcessCleanup(process);

    final stderrBuffer = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
    final uri = await _waitForNodeRuntimeUrl(stdoutLines(process));
    final client = await _RawWebSocketClient.connect(
      uri.replace(scheme: 'ws', path: '/chat', query: '', fragment: ''),
      protocols: const ['chat'],
    );
    addTearDown(client.dispose);

    final connected = await client.nextFrame(
      timeout: const Duration(seconds: 5),
    );
    expect(connected.opcode, 0x1);
    expect(utf8.decode(connected.payload), 'connected');

    await client.sendFrame(opcode: 0x1, payload: const [0xC3, 0x28]);

    final close = await client.nextFrame(timeout: const Duration(seconds: 5));
    expect(close.opcode, 0x8);
    expect(_decodeClosePayload(close.payload).code, 1007);

    await client.done.timeout(const Duration(seconds: 5));
    expect(stderrBuffer.toString(), isEmpty);
  });

  test(
    'node runtime sends 1007 close for invalid fragmented UTF-8 text messages',
    () async {
      if (!await commandAvailable('node')) {
        markTestSkipped('node is not available in the current environment');
        return;
      }

      final process = await _startNodeRuntime();
      attachProcessCleanup(process);

      final stderrBuffer = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
      final uri = await _waitForNodeRuntimeUrl(stdoutLines(process));
      final client = await _RawWebSocketClient.connect(
        uri.replace(scheme: 'ws', path: '/chat', query: '', fragment: ''),
        protocols: const ['chat'],
      );
      addTearDown(client.dispose);

      final connected = await client.nextFrame(
        timeout: const Duration(seconds: 5),
      );
      expect(connected.opcode, 0x1);
      expect(utf8.decode(connected.payload), 'connected');

      await client.sendFrame(opcode: 0x1, payload: const [0xE2], fin: false);
      await client.sendFrame(opcode: 0x0, payload: const [0x28, 0xA1]);

      final close = await client.nextFrame(timeout: const Duration(seconds: 5));
      expect(close.opcode, 0x8);
      expect(_decodeClosePayload(close.payload).code, 1007);

      await client.done.timeout(const Duration(seconds: 5));
      expect(stderrBuffer.toString(), isEmpty);
    },
  );

  test(
    'node runtime rejects websocket upgrades without a websocket key',
    () async {
      if (!await commandAvailable('node')) {
        markTestSkipped('node is not available in the current environment');
        return;
      }

      final process = await _startNodeRuntime();
      attachProcessCleanup(process);
      final uri = await _waitForNodeRuntimeUrl(stdoutLines(process));

      final response = await _sendRawHttpRequest(
        uri.replace(path: '/chat', query: '', fragment: ''),
        headers: {
          'Upgrade': 'websocket',
          'Connection': 'Upgrade',
          'Sec-WebSocket-Version': '13',
          'Sec-WebSocket-Protocol': 'chat',
        },
      );

      expect(response.statusCode, 400);
      expect(response.body, 'Bad Request');
    },
  );

  test(
    'node runtime rejects websocket upgrades with 503 when startup fails',
    () async {
      if (!await commandAvailable('node')) {
        markTestSkipped('node is not available in the current environment');
        return;
      }

      final port = await pickPort();
      final process = await _startNodeStartupFailureRuntime(port);
      attachProcessCleanup(process);

      final stderrBuffer = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
      final lines = stdoutLines(process);
      await waitForLinePrefix(
        lines,
        'STARTUP_ENTERED',
        timeout: const Duration(seconds: 5),
      );

      final exchange = await _sendRawHttpRequestAsync(
        Uri.parse('http://127.0.0.1:$port/chat'),
        headers: _webSocketUpgradeHeaders(),
      );
      await exchange.requestSent;
      await waitForLinePrefix(
        lines,
        'UPGRADE_SEEN',
        timeout: const Duration(seconds: 5),
      );
      process.stdin.writeln('release');
      await process.stdin.flush();
      final response = await exchange.response;

      expect(response.statusCode, 503);
      expect(response.statusText, 'Service Unavailable');
      expect(response.body, 'Service Unavailable');
      expect(response.header('upgrade'), isNull);
      expect(response.header('sec-websocket-accept'), isNull);
      expect(response.header('connection'), isNull);

      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 5),
      );
      expect(exitCode, isNonZero);
      expect(stderrBuffer.toString(), contains('Failed to start node runtime'));
    },
  );

  test(
    'node runtime sanitizes raw 101 upgrade responses before writing to the socket',
    () async {
      if (!await commandAvailable('node')) {
        markTestSkipped('node is not available in the current environment');
        return;
      }

      final process = await _startNodeRuntime();
      attachProcessCleanup(process);
      final uri = await _waitForNodeRuntimeUrl(stdoutLines(process));

      final response = await _sendRawHttpRequest(
        uri.replace(path: '/raw-101-upgrade', query: '', fragment: ''),
        headers: _webSocketUpgradeHeaders(),
      );

      expect(response.statusCode, 500);
      expect(response.body, 'Internal Server Error');
      expect(response.header('upgrade'), isNull);
      expect(response.header('connection'), isNull);
    },
  );

  test('node runtime rejects unsafe selected websocket subprotocols', () async {
    if (!await commandAvailable('node')) {
      markTestSkipped('node is not available in the current environment');
      return;
    }

    final process = await _startNodeRuntime();
    attachProcessCleanup(process);
    final uri = await waitForRuntimeUrl(stdoutLines(process));

    final response = await _sendRawHttpRequest(
      uri.replace(path: '/chat-requested-protocol', query: '', fragment: ''),
      headers: _webSocketUpgradeHeaders(protocols: 'bad proto'),
    );

    expect(response.statusCode, 400);
    expect(response.body, 'Bad Request');
    expect(response.rawResponse, isNot(contains('Injected: nope')));
    expect(response.header('sec-websocket-protocol'), isNull);
  });

  test(
    'node runtime strips CRLF injection from upgrade HTTP responses',
    () async {
      if (!await commandAvailable('node')) {
        markTestSkipped('node is not available in the current environment');
        return;
      }

      final process = await _startNodeRuntime();
      attachProcessCleanup(process);
      final uri = await _waitForNodeRuntimeUrl(stdoutLines(process));

      final response = await _sendRawHttpRequest(
        uri.replace(path: '/upgrade-http-response', query: '', fragment: ''),
        headers: _webSocketUpgradeHeaders(),
      );

      expect(response.statusCode, 418);
      expect(response.statusText, 'HTTP Response');
      expect(response.header('x-safe'), 'ok');
      expect(response.rawResponse, isNot(contains('Injected: nope')));
    },
  );

  test(
    'node runtime closes active websocket sessions with 1001 during shutdown',
    () async {
      if (!await commandAvailable('node')) {
        markTestSkipped('node is not available in the current environment');
        return;
      }

      final process = await _startNodeRuntime();
      attachProcessCleanup(process);

      final stderrBuffer = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
      final lines = stdoutLines(process);
      final uri = await waitForRuntimeUrl(lines);
      final client = await _RawWebSocketClient.connect(
        uri.replace(scheme: 'ws', path: '/chat', query: '', fragment: ''),
        protocols: const ['chat'],
      );
      addTearDown(client.dispose);

      final connected = await client.nextFrame(
        timeout: const Duration(seconds: 5),
      );
      expect(connected.opcode, 0x1);
      expect(utf8.decode(connected.payload), 'connected');

      final closing = await send(uri.resolve('/close-runtime'));
      expect(closing.statusCode, 200);
      expect(await closing.transform(utf8.decoder).join(), 'closing');

      final close = await client.nextFrame(timeout: const Duration(seconds: 5));
      expect(close.opcode, 0x8);
      expect(_decodeClosePayload(close.payload), (
        code: 1001,
        reason: 'Runtime shutdown',
      ));

      await client.sendClose(code: 1001, reason: 'Runtime shutdown');
      await client.done.timeout(const Duration(seconds: 5));
      expect(stderrBuffer.toString(), isEmpty);
    },
  );

  test(
    'node runtime rejects invalid close status codes received from peers',
    () async {
      if (!await commandAvailable('node')) {
        markTestSkipped('node is not available in the current environment');
        return;
      }

      final process = await _startNodeRuntime();
      attachProcessCleanup(process);
      final stderrBuffer = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
      final uri = await waitForRuntimeUrl(stdoutLines(process));
      final client = await _RawWebSocketClient.connect(
        uri.replace(scheme: 'ws', path: '/chat', query: '', fragment: ''),
        protocols: const ['chat'],
      );
      addTearDown(client.dispose);

      final connected = await client.nextFrame(
        timeout: const Duration(seconds: 5),
      );
      expect(connected.opcode, 0x1);
      expect(utf8.decode(connected.payload), 'connected');

      await client.sendClose(code: 1005, reason: 'bad');

      final close = await client.nextFrame(timeout: const Duration(seconds: 5));
      expect(close.opcode, 0x8);
      expect(_decodeClosePayload(close.payload).code, 1002);
      await client.done.timeout(const Duration(seconds: 5));

      await expectHelloEndpoint(
        uri,
        expectedBody: 'hello from node',
        expectedRuntimeHeader: 'node',
      );
      expect(stderrBuffer.toString(), isEmpty);
    },
  );

  test(
    'node runtime rejects invalid outbound close codes before encoding frames',
    () async {
      if (!await commandAvailable('node')) {
        markTestSkipped('node is not available in the current environment');
        return;
      }

      final process = await _startNodeRuntime();
      attachProcessCleanup(process);
      final stderrBuffer = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
      final uri = await waitForRuntimeUrl(stdoutLines(process));
      final webSocket = await WebSocket.connect(
        uri
            .replace(
              scheme: 'ws',
              path: '/chat-invalid-close-code',
              query: '',
              fragment: '',
            )
            .toString(),
      );
      addTearDown(() async {
        if (webSocket.closeCode == null) {
          await webSocket.close();
        }
      });

      final events = StreamIterator<Object?>(webSocket);
      expect(
        await events.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(events.current, 'connected');
      expect(
        await events.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(events.current, 'close-error:code');
      expect(
        await events.moveNext().timeout(const Duration(seconds: 5)),
        isFalse,
      );
      expect(webSocket.closeCode, 1000);
      expect(webSocket.closeReason, 'ok');
      await expectHelloEndpoint(
        uri,
        expectedBody: 'hello from node',
        expectedRuntimeHeader: 'node',
      );
      expect(stderrBuffer.toString(), isEmpty);
    },
  );

  test(
    'node runtime rejects oversized outbound close reasons before encoding frames',
    () async {
      if (!await commandAvailable('node')) {
        markTestSkipped('node is not available in the current environment');
        return;
      }

      final process = await _startNodeRuntime();
      attachProcessCleanup(process);
      final stderrBuffer = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
      final uri = await waitForRuntimeUrl(stdoutLines(process));
      final webSocket = await WebSocket.connect(
        uri
            .replace(
              scheme: 'ws',
              path: '/chat-invalid-close-reason',
              query: '',
              fragment: '',
            )
            .toString(),
      );
      addTearDown(() async {
        if (webSocket.closeCode == null) {
          await webSocket.close();
        }
      });

      final events = StreamIterator<Object?>(webSocket);
      expect(
        await events.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(events.current, 'connected');
      expect(
        await events.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(events.current, 'close-error:reason');
      expect(
        await events.moveNext().timeout(const Duration(seconds: 5)),
        isFalse,
      );
      expect(webSocket.closeCode, 1000);
      expect(webSocket.closeReason, 'ok');
      await expectHelloEndpoint(
        uri,
        expectedBody: 'hello from node',
        expectedRuntimeHeader: 'node',
      );
      expect(stderrBuffer.toString(), isEmpty);
    },
  );

  test('_encodeClosePayload rejects a close reason without a status code', () {
    expect(
      () => _encodeClosePayload(null, 'reason'),
      throwsA(isA<ArgumentError>()),
    );
  });
}

Future<Process> _startNodeRuntime() async {
  final appDir = '$workspacePath/integration_test/node/app';
  await buildFixture(appDir);
  return startFixture(appDir);
}

Future<Process> _startNodeStartupFailureRuntime(int port) async {
  final appDir = '$workspacePath/integration_test/node/startup_failure_app';
  await buildFixture(appDir);
  return startFixture(appDir, environment: {'OSRV_TEST_PORT': '$port'});
}

Future<Uri> _waitForNodeRuntimeUrl(Stream<String> lines) {
  return waitForRuntimeUrl(lines, timeout: const Duration(seconds: 20));
}

Map<String, String> _webSocketUpgradeHeaders({String protocols = 'chat'}) {
  return {
    'Upgrade': 'websocket',
    'Connection': 'Upgrade',
    'Sec-WebSocket-Version': '13',
    'Sec-WebSocket-Key': base64.encode(
      List<int>.generate(16, (index) => index + 1),
    ),
    'Sec-WebSocket-Protocol': protocols,
  };
}

Future<_RawHttpResponse> _sendRawHttpRequest(
  Uri uri, {
  String method = 'GET',
  Map<String, String> headers = const <String, String>{},
  String? body,
}) async {
  final exchange = await _sendRawHttpRequestAsync(
    uri,
    method: method,
    headers: headers,
    body: body,
  );
  await exchange.requestSent;
  return exchange.response;
}

Future<_RawHttpRequestExchange> _sendRawHttpRequestAsync(
  Uri uri, {
  String method = 'GET',
  Map<String, String> headers = const <String, String>{},
  String? body,
}) async {
  final socket = await Socket.connect(uri.host, uri.port);
  final response = () async {
    try {
      final responseBytes = await socket.fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (builder, chunk) {
          builder.add(chunk);
          return builder;
        },
      );
      final rawResponse = latin1.decode(responseBytes.takeBytes());
      return _RawHttpResponse.parse(rawResponse);
    } finally {
      await socket.close();
    }
  }();

  final path = uri.path.isEmpty ? '/' : uri.path;
  final target = uri
      .replace(scheme: '', host: '', port: 0, path: path)
      .toString();
  final request = StringBuffer()
    ..write('$method $target HTTP/1.1\r\n')
    ..write('Host: ${uri.host}:${uri.port}\r\n');
  headers.forEach((key, value) {
    request.write('$key: $value\r\n');
  });
  if (body != null) {
    request.write('Content-Length: ${utf8.encode(body).length}\r\n');
  }
  request.write('\r\n');
  if (body != null) {
    request.write(body);
  }

  socket.add(utf8.encode(request.toString()));
  await socket.flush();
  await socket.close();

  return _RawHttpRequestExchange(
    requestSent: Future<void>.value(),
    response: response,
  );
}

final class _RawHttpResponse {
  const _RawHttpResponse({
    required this.statusCode,
    required this.statusText,
    required this.headers,
    required this.body,
    required this.rawResponse,
  });

  factory _RawHttpResponse.parse(String rawResponse) {
    final parts = rawResponse.split('\r\n\r\n');
    final head = parts.first;
    final body = parts.length > 1 ? parts.sublist(1).join('\r\n\r\n') : '';
    final lines = head.split('\r\n');
    final statusLine = lines.first.split(' ');
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      if (line.isEmpty) {
        continue;
      }
      final separator = line.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      headers[line.substring(0, separator).toLowerCase()] = line
          .substring(separator + 1)
          .trim();
    }

    return _RawHttpResponse(
      statusCode: int.parse(statusLine[1]),
      statusText: statusLine.skip(2).join(' '),
      headers: headers,
      body: body,
      rawResponse: rawResponse,
    );
  }

  final int statusCode;
  final String statusText;
  final Map<String, String> headers;
  final String body;
  final String rawResponse;

  String? header(String name) => headers[name.toLowerCase()];
}

final class _RawHttpRequestExchange {
  const _RawHttpRequestExchange({
    required this.requestSent,
    required this.response,
  });

  final Future<void> requestSent;
  final Future<_RawHttpResponse> response;
}

final class _RawWebSocketClient {
  _RawWebSocketClient._(this._socket) {
    _subscription = _socket.listen(
      _onData,
      onDone: _onDone,
      onError: _onError,
      cancelOnError: true,
    );
  }

  static Future<_RawWebSocketClient> connect(
    Uri uri, {
    List<String> protocols = const <String>[],
  }) async {
    final socket = await Socket.connect(uri.host, uri.port);
    final client = _RawWebSocketClient._(socket);

    final path = uri.path.isEmpty ? '/' : uri.path;
    final target = uri
        .replace(scheme: '', host: '', port: 0, path: path)
        .toString();
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
  final _frames = <_ServerFrame>[];
  final _pendingFrames = <Completer<_ServerFrame>>[];
  final _handshake = Completer<_HandshakeResponse>();
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

  Future<void> sendClose({int? code, String? reason}) {
    return sendFrame(opcode: 0x8, payload: _encodeClosePayload(code, reason));
  }

  Future<_ServerFrame> nextFrame({Duration? timeout}) async {
    final queued = _takeFrame();
    if (queued != null) {
      return queued;
    }

    final completer = Completer<_ServerFrame>();
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
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      if (line.isEmpty) {
        continue;
      }
      final separator = line.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      headers[line.substring(0, separator).toLowerCase()] = line
          .substring(separator + 1)
          .trim();
    }

    _handshakeComplete = true;
    if (!_handshake.isCompleted) {
      _handshake.complete(_HandshakeResponse(statusCode, headers));
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
      _queueFrame(_ServerFrame(frame.opcode, frame.payload, frame.fin));
    }
    return offset;
  }

  void _queueFrame(_ServerFrame frame) {
    if (_pendingFrames.isNotEmpty) {
      _pendingFrames.removeAt(0).complete(frame);
      return;
    }
    _frames.add(frame);
  }

  _ServerFrame? _takeFrame() {
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

final class _HandshakeResponse {
  const _HandshakeResponse(this.statusCode, this.headers);

  final int statusCode;
  final Map<String, String> headers;
}

final class _ServerFrame {
  const _ServerFrame(this.opcode, this.payload, this.fin);

  final int opcode;
  final Uint8List payload;
  final bool fin;
}

final class _ParsedServerFrame {
  const _ParsedServerFrame({
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

_ParsedServerFrame? _tryParseServerFrame(Uint8List bytes, int offset) {
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

  return _ParsedServerFrame(
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
  const mask = [0x11, 0x22, 0x33, 0x44];
  final header = BytesBuilder(copy: false)
    ..addByte((fin ? 0x80 : 0x00) | (opcode & 0x0F));

  if (payload.length < 126) {
    header.addByte(0x80 | payload.length);
  } else if (payload.length <= 0xFFFF) {
    header
      ..addByte(0x80 | 126)
      ..addByte((payload.length >> 8) & 0xFF)
      ..addByte(payload.length & 0xFF);
  } else {
    header.addByte(0x80 | 127);
    for (var shift = 56; shift >= 0; shift -= 8) {
      header.addByte((payload.length >> shift) & 0xFF);
    }
  }

  header.add(mask);
  final maskedPayload = Uint8List.fromList(payload);
  for (var i = 0; i < maskedPayload.length; i++) {
    maskedPayload[i] ^= mask[i % 4];
  }
  header.add(maskedPayload);
  return header.takeBytes();
}

Uint8List _encodeClosePayload(int? code, String? reason) {
  if (code == null && (reason == null || reason.isEmpty)) {
    return Uint8List(0);
  }
  if (code == null) {
    throw ArgumentError.value(
      reason,
      'reason',
      'Close reason requires a status code.',
    );
  }

  final builder = BytesBuilder(copy: false);
  builder
    ..addByte((code >> 8) & 0xFF)
    ..addByte(code & 0xFF);
  if (reason != null && reason.isNotEmpty) {
    builder.add(utf8.encode(reason));
  }
  return builder.takeBytes();
}

({int? code, String reason}) _decodeClosePayload(Uint8List payload) {
  if (payload.length < 2) {
    return (code: null, reason: '');
  }

  final code = (payload[0] << 8) | payload[1];
  final reason = payload.length > 2 ? utf8.decode(payload.sublist(2)) : '';
  return (code: code, reason: reason);
}
