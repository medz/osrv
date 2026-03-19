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

        await expectWebSocketEcho(baseUri);
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
