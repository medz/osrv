@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('cloudflare worker serves requests over wrangler local dev', () async {
    final wrangler = await _resolveWrangler();
    if (wrangler == null) {
      markTestSkipped('wrangler is not available in the current environment');
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp('osrv_cf_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    final compiledPath = '${tempDir.path}/worker.dart.js';
    final compile = await Process.run('dart', [
      'compile',
      'js',
      'test/fixtures/cloudflare_runtime_worker.dart',
      '-o',
      compiledPath,
    ], workingDirectory: _workspacePath);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');

    await File('${tempDir.path}/worker.mjs').writeAsString(_workerWrapper);
    await File(
      '${tempDir.path}/wrangler.json',
    ).writeAsString(_wranglerConfig(name: 'osrv-test-cloudflare'));

    final port = await _pickPort();
    final process = await Process.start(wrangler.$1, [
      ...wrangler.$2,
      'dev',
      '--local',
      '--ip',
      '127.0.0.1',
      '--port',
      '$port',
      '--log-level',
      'error',
    ], workingDirectory: tempDir.path);
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
    final stdoutBuffer = StringBuffer();
    process.stdout.transform(utf8.decoder).listen(stdoutBuffer.write);

    final baseUri = Uri.parse('http://127.0.0.1:$port');
    await _waitForHttpServer(baseUri.resolve('/hello'));

    final hello = await _send(
      baseUri.resolve('/hello'),
      headers: {'accept': 'text/plain'},
    );
    expect(hello.statusCode, 200);
    expect(await hello.transform(utf8.decoder).join(), 'hello from cloudflare');
    expect(hello.headers.value('x-runtime'), 'cloudflare');

    final meta = await _send(baseUri.resolve('/meta'));
    expect(meta.statusCode, 200);
    expect(jsonDecode(await meta.transform(utf8.decoder).join()), {
      'runtime': 'cloudflare',
      'kind': 'entry',
      'capabilities': {
        'streaming': true,
        'websocket': true,
        'fileSystem': false,
        'backgroundTask': true,
        'rawTcp': false,
        'nodeCompat': true,
      },
    });

    final echo = await _send(
      baseUri.resolve('/echo?mode=full'),
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
    });

    final stream = await _send(baseUri.resolve('/stream'));
    expect(stream.statusCode, 200);
    expect(await stream.transform(utf8.decoder).join(), 'hello cloudflare');
    expect(stream.headers.value('x-stream'), 'yes');

    final handled = await _send(baseUri.resolve('/error'));
    expect(handled.statusCode, 418);
    expect(await handled.transform(utf8.decoder).join(), 'handled cloudflare');

    final raw101 = await _send(baseUri.resolve('/raw-101'));
    expect(raw101.statusCode, 500);
    expect(
      await raw101.transform(utf8.decoder).join(),
      'Internal Server Error',
    );

    final webSocket = await WebSocket.connect(
      baseUri.replace(scheme: 'ws', path: '/chat').toString(),
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
    if (process.kill(ProcessSignal.sigterm)) {
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
    await stderrDone;

    _expectNoUnexpectedWranglerStderr(
      stderrBuffer.toString(),
      stdout: stdoutBuffer.toString(),
    );
  });
}

final _workspacePath = Directory.current.path;
final _wranglerFromExample =
    '$_workspacePath/example/node_modules/.bin/wrangler';

const _workerWrapper = '''
import "./worker.dart.js";

export default { fetch: globalThis.__osrv_fetch__ };
''';

String _wranglerConfig({required String name}) => jsonEncode({
  'name': name,
  'main': './worker.mjs',
  'compatibility_date': '2026-03-01',
  'workers_dev': true,
});

Future<(String, List<String>)?> _resolveWrangler() async {
  final exampleWrangler = File(_wranglerFromExample);
  if (await exampleWrangler.exists()) {
    return (_wranglerFromExample, const <String>[]);
  }

  try {
    final result = await Process.run('npx', [
      '--yes',
      'wrangler@4.75.0',
      '--version',
    ]);
    if (result.exitCode == 0) {
      return ('npx', const ['--yes', 'wrangler@4.75.0']);
    }
  } on ProcessException {
    return null;
  }

  return null;
}

Future<int> _pickPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<void> _waitForHttpServer(Uri uri) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));

  while (DateTime.now().isBefore(deadline)) {
    try {
      final response = await _send(uri).timeout(const Duration(seconds: 2));
      await response.drain<void>();
      return;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  throw StateError('Cloudflare worker did not become ready at $uri');
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

void _expectNoUnexpectedWranglerStderr(
  String stderr, {
  required String stdout,
}) {
  final normalized = stderr
      .replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .where((line) => !_isKnownWranglerWebSocketNoise(line))
      .toList(growable: false);

  expect(normalized, isEmpty, reason: 'stdout:\n$stdout\nstderr:\n$stderr');
}

bool _isKnownWranglerWebSocketNoise(String line) {
  return line.contains(
        "The Workers runtime canceled this request because it detected that your Worker's code had hung and would never generate a response.",
      ) ||
      line.contains(
        'https://developers.cloudflare.com/workers/observability/errors/',
      );
}
