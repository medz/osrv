@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('deno runtime serves requests and shuts down cleanly', () async {
    if (!await _hasDeno()) {
      markTestSkipped('deno is not available in the current environment');
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp('osrv_deno_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    final compiledPath = '${tempDir.path}/deno_runtime_server.js';
    final compile = await Process.run('dart', [
      'compile',
      'js',
      'test/fixtures/deno_runtime_server.dart',
      '-o',
      compiledPath,
    ], workingDirectory: _workspacePath);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');

    final process = await Process.start('deno', [
      'run',
      '--allow-net',
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
    final stdoutLines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();

    final uri = await _waitForRuntimeUrl(stdoutLines);
    final lifecycleFuture = _waitForLifecycle(stdoutLines);

    final hello = await _send(
      uri.resolve('/hello'),
      headers: {'accept': 'text/plain'},
    );
    expect(hello.statusCode, 200);
    expect(await hello.transform(utf8.decoder).join(), 'hello from deno');
    expect(hello.headers.value('x-runtime'), 'deno');

    final meta = await _send(uri.resolve('/meta'));
    expect(meta.statusCode, 200);
    expect(jsonDecode(await meta.transform(utf8.decoder).join()), {
      'runtime': 'deno',
      'kind': 'server',
      'capabilities': {
        'streaming': true,
        'websocket': false,
        'fileSystem': true,
        'backgroundTask': true,
        'rawTcp': true,
        'nodeCompat': true,
      },
      'lifecycle': {'onStartHasDeno': true, 'onStartHasServer': true},
    });

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
      'hasDenoRequest': true,
    });

    final stream = await _send(uri.resolve('/stream'));
    expect(stream.statusCode, 200);
    expect(await stream.transform(utf8.decoder).join(), 'hello deno');
    expect(stream.headers.value('x-stream'), 'yes');

    final handled = await _send(uri.resolve('/error'));
    expect(handled.statusCode, 418);
    expect(await handled.transform(utf8.decoder).join(), 'handled deno');

    final stopwatch = Stopwatch()..start();
    final closing = await _send(uri.resolve('/wait-close'));
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
}

final _workspacePath = Directory.current.path;

Future<bool> _hasDeno() async {
  try {
    final result = await Process.run('deno', ['--version']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Future<Uri> _waitForRuntimeUrl(Stream<String> stdoutLines) async {
  await for (final line in stdoutLines.timeout(const Duration(seconds: 10))) {
    if (line.startsWith('URL:')) {
      return Uri.parse(line.substring(4));
    }
  }

  throw StateError('Deno runtime did not print a startup URL.');
}

Future<Map<String, dynamic>> _waitForLifecycle(
  Stream<String> stdoutLines,
) async {
  await for (final line in stdoutLines.timeout(const Duration(seconds: 10))) {
    if (line.startsWith('LIFECYCLE:')) {
      return jsonDecode(line.substring(10)) as Map<String, dynamic>;
    }
  }

  throw StateError('Deno runtime did not print lifecycle state.');
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
