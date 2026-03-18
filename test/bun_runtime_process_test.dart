@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('bun runtime serves requests and shuts down cleanly', () async {
    if (!await _hasBun()) {
      markTestSkipped('bun is not available in the current environment');
    }

    final tempDir = await Directory.systemTemp.createTemp('osrv_bun_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    final compiledPath = '${tempDir.path}/bun_runtime_server.js';
    final compile = await Process.run('dart', [
      'compile',
      'js',
      'test/fixtures/bun_runtime_server.dart',
      '-o',
      compiledPath,
    ], workingDirectory: _workspacePath);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');

    final process = await Process.start('bun', [
      compiledPath,
    ], workingDirectory: _workspacePath);
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
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write)
        .asFuture<void>();
    final uri = await _waitForRuntimeUrl(process.stdout);

    final hello = await _send(
      uri.resolve('/hello'),
      headers: {'accept': 'text/plain'},
    );
    expect(hello.statusCode, 200);
    expect(await hello.transform(utf8.decoder).join(), 'hello from bun');
    expect(hello.headers.value('x-runtime'), 'bun');

    final echo = await _send(
      uri.resolve('/echo?mode=full'),
      method: 'POST',
      body: 'payload',
      headers: {'x-test': 'yes'},
    );
    expect(echo.statusCode, 200);
    expect(jsonDecode(await echo.transform(utf8.decoder).join()), {
      'method': 'POST',
      'path': '/echo',
      'query': 'full',
      'header': 'yes',
      'body': 'payload',
      'hasBunRequest': true,
    });

    final stream = await _send(uri.resolve('/stream'));
    expect(stream.statusCode, 200);
    expect(await stream.transform(utf8.decoder).join(), 'hello bun');
    expect(stream.headers.value('x-stream'), 'yes');

    final handled = await _send(uri.resolve('/error'));
    expect(handled.statusCode, 418);
    expect(await handled.transform(utf8.decoder).join(), 'handled bun');

    final stopwatch = Stopwatch()..start();
    final closing = await _send(uri.resolve('/wait-close'));
    expect(closing.statusCode, 200);
    expect(await closing.transform(utf8.decoder).join(), 'closing');

    final exitCode = await process.exitCode.timeout(const Duration(seconds: 5));
    stopwatch.stop();
    await stderrDone;

    expect(exitCode, 0, reason: stderrBuffer.toString());
    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(150));
    expect(stderrBuffer.toString(), isEmpty);
  });

  test('bun websocket server upgrades requests and echoes messages', () async {
    if (!await _hasBun()) {
      markTestSkipped('bun is not available in the current environment');
    }

    final tempDir = await Directory.systemTemp.createTemp('osrv_bun_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    final compiledPath = '${tempDir.path}/bun_runtime_server.js';
    final compile = await Process.run('dart', [
      'compile',
      'js',
      'test/fixtures/bun_runtime_server.dart',
      '-o',
      compiledPath,
    ], workingDirectory: _workspacePath);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');

    final process = await Process.start('bun', [
      compiledPath,
    ], workingDirectory: _workspacePath);
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
    final uri = await _waitForRuntimeUrl(process.stdout);

    final hello = await _send(
      uri.resolve('/hello'),
      headers: {'accept': 'text/plain'},
    );
    expect(hello.statusCode, 200);
    expect(await hello.transform(utf8.decoder).join(), 'hello from bun');
    expect(hello.headers.value('x-runtime'), 'bun');

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
    expect(await events.moveNext().timeout(const Duration(seconds: 5)), isTrue);
    expect(events.current, 'connected');

    webSocket.add('ping');
    expect(await events.moveNext().timeout(const Duration(seconds: 5)), isTrue);
    expect(events.current, 'echo:ping');

    await webSocket.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(stderrBuffer.toString(), isEmpty);
  });
}

final _workspacePath = Directory.current.path;

Future<bool> _hasBun() async {
  try {
    final result = await Process.run('bun', ['--version']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Future<Uri> _waitForRuntimeUrl(Stream<List<int>> stdout) async {
  final lines = stdout.transform(utf8.decoder).transform(const LineSplitter());

  await for (final line in lines.timeout(const Duration(seconds: 10))) {
    if (line.startsWith('URL:')) {
      return Uri.parse(line.substring(4));
    }
  }

  throw StateError('Bun runtime did not print a startup URL.');
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
