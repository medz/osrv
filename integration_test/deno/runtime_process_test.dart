@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../shared/runtime_contract.dart';
import '../shared/test_support.dart';

void main() {
  test('deno runtime serves requests and shuts down cleanly', () async {
    if (!await commandAvailable('deno')) {
      markTestSkipped('deno is not available in the current environment');
      return;
    }

    final process = await _startDenoRuntime();

    final stderrBuffer = StringBuffer();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write)
        .asFuture<void>();
    final lines = stdoutLines(process);

    final uri = await waitForRuntimeUrl(lines);
    final lifecycleFuture = _waitForLifecycle(lines);

    await expectHelloEndpoint(
      uri,
      expectedBody: 'hello from deno',
      expectedRuntimeHeader: 'deno',
    );

    final meta = await send(uri.resolve('/meta'));
    expect(meta.statusCode, 200);
    expect(jsonDecode(await meta.transform(utf8.decoder).join()), {
      'runtime': 'deno',
      'kind': 'server',
      'capabilities': {
        'streaming': true,
        'websocket': true,
        'fileSystem': true,
        'backgroundTask': true,
        'rawTcp': true,
        'nodeCompat': true,
      },
      'lifecycle': {'onStartHasDeno': true, 'onStartHasServer': true},
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
    expect(jsonDecode(await postMeta.transform(utf8.decoder).join()), {
      'runtime': 'deno',
      'kind': 'server',
      'capabilities': {
        'streaming': true,
        'websocket': true,
        'fileSystem': true,
        'backgroundTask': true,
        'rawTcp': true,
        'nodeCompat': true,
      },
      'lifecycle': {'onStartHasDeno': true, 'onStartHasServer': true},
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
      'hasDenoRequest': true,
    });

    final stream = await send(uri.resolve('/stream'));
    expect(stream.statusCode, 200);
    expect(await stream.transform(utf8.decoder).join(), 'hello deno');
    expect(stream.headers.value('x-stream'), 'yes');

    final handled = await send(uri.resolve('/error'));
    expect(handled.statusCode, 418);
    expect(await handled.transform(utf8.decoder).join(), 'handled deno');

    final stopwatch = Stopwatch()..start();
    final closing = await send(uri.resolve('/wait-close'));
    expect(closing.statusCode, 200);
    expect(await closing.transform(utf8.decoder).join(), 'closing');

    final exitCode = await process.exitCode.timeout(const Duration(seconds: 5));
    stopwatch.stop();
    final lifecycle = await lifecycleFuture;
    await stderrDone;

    expect(exitCode, 0, reason: stderrBuffer.toString());
    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(150));
    expect(lifecycle, {'onStopHasDeno': true, 'onStopHasServer': true});
    expect(stderrBuffer.toString(), isEmpty);
  });

  test('deno websocket server upgrades requests and echoes messages', () async {
    if (!await commandAvailable('deno')) {
      markTestSkipped('deno is not available in the current environment');
      return;
    }

    final process = await _startDenoRuntime();

    final stderrBuffer = StringBuffer();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write)
        .asFuture<void>();
    final lines = stdoutLines(process);

    final uri = await waitForRuntimeUrl(lines);

    await expectHelloEndpoint(
      uri,
      expectedBody: 'hello from deno',
      expectedRuntimeHeader: 'deno',
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

Future<Map<String, dynamic>> _waitForLifecycle(Stream<String> lines) async {
  final value = await waitForLinePrefix(
    lines,
    'LIFECYCLE:',
    reason: 'Deno runtime did not print lifecycle state.',
  );
  return jsonDecode(value) as Map<String, dynamic>;
}

Future<Process> _startDenoRuntime() async {
  final appDir = '$workspacePath/integration_test/deno/app';
  await buildFixture(appDir);
  return startFixture(appDir);
}
