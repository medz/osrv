@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'node runtime websocket server upgrades requests and echoes messages',
    () async {
      if (!await _hasNode()) {
        markTestSkipped('node is not available in the current environment');
        return;
      }

      final process = await _startNodeRuntime();
      addTearDown(() async {
        if (process.kill(ProcessSignal.sigterm)) {
          await process.exitCode.timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              process.kill(ProcessSignal.sigkill);
              return -1;
            },
          );
        }
      });

      final stderrBuffer = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
      final stdoutLines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();

      final uri = await _waitForRuntimeUrl(stdoutLines);

      final meta = await _send(uri.resolve('/meta'));
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

      final hello = await _send(
        uri.resolve('/hello'),
        headers: {'accept': 'text/plain'},
      );
      expect(hello.statusCode, 200);
      expect(await hello.transform(utf8.decoder).join(), 'hello from node');
      expect(hello.headers.value('x-runtime'), 'node');

      final webSocket = await WebSocket.connect(
        uri
            .replace(scheme: 'ws', path: '/chat', query: '', fragment: '')
            .toString(),
        protocols: ['chat'],
      );
      addTearDown(() async {
        if (webSocket.closeCode == null) {
          await webSocket.close();
        }
      });

      final events = StreamIterator<Object?>(webSocket);
      expect(webSocket.protocol, 'chat');
      expect(
        await events.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(events.current, 'connected');

      webSocket.add('ping');
      expect(
        await events.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(events.current, 'echo:ping');

      await webSocket.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(stderrBuffer.toString(), isEmpty);
    },
  );

  test('node runtime close waits for active websocket sessions', () async {
    if (!await _hasNode()) {
      markTestSkipped('node is not available in the current environment');
      return;
    }

    final process = await _startNodeRuntime();
    addTearDown(() async {
      if (process.kill(ProcessSignal.sigterm)) {
        await process.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      }
    });

    final stderrBuffer = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
    final stdoutLines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();

    final uri = await _waitForRuntimeUrl(stdoutLines);
    final webSocket = await WebSocket.connect(
      uri
          .replace(scheme: 'ws', path: '/chat', query: '', fragment: '')
          .toString(),
      protocols: ['chat'],
    );

    final events = StreamIterator<Object?>(webSocket);
    expect(await events.moveNext().timeout(const Duration(seconds: 5)), isTrue);
    expect(events.current, 'connected');

    var exited = false;
    unawaited(
      process.exitCode.then((_) {
        exited = true;
      }),
    );

    final closing = await _send(uri.resolve('/close-runtime'));
    expect(closing.statusCode, 200);
    expect(await closing.transform(utf8.decoder).join(), 'closing');

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(exited, isFalse);

    await webSocket.close();
    final exitCode = await process.exitCode.timeout(const Duration(seconds: 5));

    expect(exitCode, 0, reason: stderrBuffer.toString());
    expect(stderrBuffer.toString(), isEmpty);
  });
}

final _workspacePath = Directory.current.path;

Future<bool> _hasNode() async {
  try {
    final result = await Process.run('node', ['--version']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Future<Process> _startNodeRuntime() async {
  final tempDir = await Directory.systemTemp.createTemp('osrv_node_test_');
  final compiledPath = '${tempDir.path}/node_runtime_server.js';
  final wrapperPath = '${tempDir.path}/node_runtime_server.mjs';
  final compile = await Process.run('dart', [
    'compile',
    'js',
    'test/fixtures/node_runtime_server.dart',
    '-o',
    compiledPath,
  ], workingDirectory: _workspacePath);
  expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');

  await File(wrapperPath).writeAsString('''
globalThis.self ??= globalThis;
import './node_runtime_server.js';
''');

  final process = await Process.start('node', [
    wrapperPath,
  ], workingDirectory: _workspacePath);
  addTearDown(() => tempDir.delete(recursive: true));
  return process;
}

Future<Uri> _waitForRuntimeUrl(Stream<String> stdoutLines) async {
  await for (final line in stdoutLines.timeout(const Duration(seconds: 10))) {
    if (line.startsWith('URL:')) {
      return Uri.parse(line.substring(4));
    }
  }

  throw StateError('Node runtime did not print a startup URL.');
}

Future<HttpClientResponse> _send(
  Uri uri, {
  String method = 'GET',
  String? body,
  Map<String, String>? headers,
}) async {
  final client = HttpClient();
  final request = await client.openUrl(method, uri);
  headers?.forEach(request.headers.set);
  if (body != null) {
    request.write(body);
  }
  final response = await request.close();
  client.close();
  return response;
}
