@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../shared/runtime_contract.dart';
import '../shared/test_support.dart';

void main() {
  test(
    'cloudflare manual websocket client fails fast on unexpected text frames',
    () async {
      if (!await commandAvailable('npm') || !await commandAvailable('node')) {
        markTestSkipped(
          'npm or node is not available in the current environment',
        );
        return;
      }

      final appDir = '$workspacePath/integration_test/cloudflare/app';
      await buildFixture(appDir);

      final server = await _startManualClientFixtureServer(appDir);
      final stdoutLinesStream = stdoutLines(server);
      final serverStderr = StringBuffer();
      final stderrSub = server.stderr
          .transform(utf8.decoder)
          .listen(serverStderr.write);
      final url = await waitForLinePrefix(
        stdoutLinesStream,
        'URL:',
        reason: 'Manual websocket fixture server did not print a URL.',
      );

      try {
        final stopwatch = Stopwatch()..start();
        final result = await Process.run('node', [
          './manual_ws_client.mjs',
          url,
          'chat',
        ], workingDirectory: appDir);
        stopwatch.stop();

        expect(result.exitCode, isNonZero, reason: '${result.stdout}');
        expect(
          result.stderr,
          contains('unexpected text frame'),
          reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
        );
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 2)),
          reason: 'manual client should fail immediately on unexpected text',
        );
      } finally {
        await stderrSub.cancel();
        if (server.kill(ProcessSignal.sigterm)) {
          await server.exitCode.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              server.kill(ProcessSignal.sigkill);
              return -1;
            },
          );
        }
      }
    },
  );

  test(
    'cloudflare worker serves requests over wrangler local dev',
    () async {
      if (!await commandAvailable('npm')) {
        markTestSkipped('npm is not available in the current environment');
        return;
      }

      final appDir = '$workspacePath/integration_test/cloudflare/app';
      await buildFixture(appDir);
      final port = await _pickPort();
      final process = await startFixture(
        appDir,
        environment: {'HOST': '127.0.0.1', 'PORT': '$port'},
      );
      final stderrBuffer = StringBuffer();
      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .listen(stderrBuffer.write);
      final stdoutBuffer = StringBuffer();
      final stdoutSub = process.stdout
          .transform(utf8.decoder)
          .listen(stdoutBuffer.write);
      try {
        final baseUri = Uri.parse('http://127.0.0.1:$port');
        await waitForHttpServer(baseUri.resolve('/hello'));

        await expectHelloEndpoint(
          baseUri,
          expectedBody: 'hello from cloudflare',
          expectedRuntimeHeader: 'cloudflare',
        );

        final meta = await send(baseUri.resolve('/meta'));
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

        final echo = await send(
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

        final stream = await send(baseUri.resolve('/stream'));
        expect(stream.statusCode, 200);
        expect(await stream.transform(utf8.decoder).join(), 'hello cloudflare');
        expect(stream.headers.value('x-stream'), 'yes');

        final handled = await send(baseUri.resolve('/error'));
        expect(handled.statusCode, 418);
        expect(
          await handled.transform(utf8.decoder).join(),
          'handled cloudflare',
        );

        final raw101 = await send(baseUri.resolve('/raw-101'));
        expect(raw101.statusCode, 500);
        expect(
          await raw101.transform(utf8.decoder).join(),
          'Internal Server Error',
        );

        await _expectManualWebSocketClientCleanClose(appDir, baseUri);
      } finally {
        await _stopWranglerProcess(
          process,
          stdoutSub: stdoutSub,
          stderrSub: stderrSub,
          stdoutBuffer: stdoutBuffer,
          stderrBuffer: stderrBuffer,
        );
        _expectNoUnexpectedWranglerStderr(
          stderrBuffer.toString(),
          stdout: stdoutBuffer.toString(),
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _stopWranglerProcess(
  Process process, {
  required StreamSubscription<String> stdoutSub,
  required StreamSubscription<String> stderrSub,
  required StringBuffer stdoutBuffer,
  required StringBuffer stderrBuffer,
}) async {
  process.kill(ProcessSignal.sigterm);

  await process.exitCode.timeout(
    const Duration(seconds: 10),
    onTimeout: () async {
      process.kill(ProcessSignal.sigkill);
      return process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException(
          'Wrangler did not exit after SIGTERM/SIGKILL.\nstdout:\n$stdoutBuffer\nstderr:\n$stderrBuffer',
        ),
      );
    },
  );
  await stdoutSub.cancel();
  await stderrSub.cancel();
}

Future<int> _pickPort() async => pickPort();

Future<Process> _startManualClientFixtureServer(String appDir) async {
  final process = await Process.start('node', [
    '--input-type=module',
    '-e',
    '''
import { WebSocketServer } from 'ws';

const server = new WebSocketServer({ host: '127.0.0.1', port: 0 });
server.on('listening', () => {
  const address = server.address();
  console.log(`URL:ws://127.0.0.1:\${address.port}`);
});
server.on('connection', (socket) => {
  socket.send('connected');
  socket.send('unexpected');
});
''',
  ], workingDirectory: appDir);
  attachProcessCleanup(process);
  return process;
}

Future<void> _expectManualWebSocketClientCleanClose(
  String appDir,
  Uri baseUri,
) async {
  // Cloudflare websocket behavior is exercised against the real local JS
  // runtime, so use a JS client here as well and wait for an explicit clean
  // close before considering the request complete.
  final result = await Process.run('node', [
    './manual_ws_client.mjs',
    baseUri.replace(scheme: 'ws', path: '/chat').toString(),
    'chat',
  ], workingDirectory: appDir);
  expect(
    result.exitCode,
    0,
    reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
  );
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
