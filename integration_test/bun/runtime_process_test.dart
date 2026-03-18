@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../shared/runtime_contract.dart';
import '../shared/test_support.dart';

void main() {
  test('bun runtime serves requests and shuts down cleanly', () async {
    if (!await commandAvailable('bun')) {
      markTestSkipped('bun is not available in the current environment');
      return;
    }

    final process = await _startBunRuntime();

    final stderrBuffer = StringBuffer();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write)
        .asFuture<void>();
    final uri = await waitForRuntimeUrl(stdoutLines(process));

    await expectHelloEndpoint(
      uri,
      expectedBody: 'hello from bun',
      expectedRuntimeHeader: 'bun',
    );

    final meta = await send(uri.resolve('/meta'));
    expect(meta.statusCode, 200);
    expect(jsonDecode(await meta.transform(utf8.decoder).join()), {
      'runtime': 'bun',
      'kind': 'server',
      'capabilities': {
        'streaming': true,
        'websocket': true,
        'fileSystem': true,
        'backgroundTask': true,
        'rawTcp': false,
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
      'runtime': 'bun',
      'kind': 'server',
      'capabilities': {
        'streaming': true,
        'websocket': true,
        'fileSystem': true,
        'backgroundTask': true,
        'rawTcp': false,
        'nodeCompat': true,
      },
      'request': {'hasWebSocket': true, 'upgrade': false},
    });

    final echo = await send(
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

    final stream = await send(uri.resolve('/stream'));
    expect(stream.statusCode, 200);
    expect(await stream.transform(utf8.decoder).join(), 'hello bun');
    expect(stream.headers.value('x-stream'), 'yes');

    final handled = await send(uri.resolve('/error'));
    expect(handled.statusCode, 418);
    expect(await handled.transform(utf8.decoder).join(), 'handled bun');

    final stopwatch = Stopwatch()..start();
    final closing = await send(uri.resolve('/wait-close'));
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
    if (!await commandAvailable('bun')) {
      markTestSkipped('bun is not available in the current environment');
      return;
    }

    final process = await _startBunRuntime();

    final stderrBuffer = StringBuffer();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write)
        .asFuture<void>();
    final uri = await waitForRuntimeUrl(stdoutLines(process));

    await expectHelloEndpoint(
      uri,
      expectedBody: 'hello from bun',
      expectedRuntimeHeader: 'bun',
    );
    await expectWebSocketEcho(uri);
    final closing = await send(uri.resolve('/wait-close'));
    expect(closing.statusCode, 200);
    expect(await closing.transform(utf8.decoder).join(), 'closing');
    final exitCode = await process.exitCode.timeout(const Duration(seconds: 5));
    await stderrDone;

    expect(exitCode, 0, reason: stderrBuffer.toString());
    expect(stderrBuffer.toString(), isEmpty);
  });
}

Future<Process> _startBunRuntime() async {
  final appDir = '$workspacePath/integration_test/bun/app';
  await buildFixture(appDir);
  return startFixture(appDir);
}
