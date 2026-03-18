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

      final uri = await waitForRuntimeUrl(lines);

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

    final uri = await waitForRuntimeUrl(lines);
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

    final closing = await send(uri.resolve('/close-runtime'));
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

Future<Process> _startNodeRuntime() async {
  final appDir = '$workspacePath/integration_test/node/app';
  await buildFixture(appDir);
  return startFixture(appDir);
}
