import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

final workspacePath = Directory.current.path;

Future<bool> commandAvailable(
  String executable, {
  List<String> args = const ['--version'],
}) async {
  try {
    final result = await Process.run(executable, args);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Future<void> buildFixture(
  String appDir, {
  Map<String, String>? environment,
}) async {
  final buildScript = File('$appDir/build.sh');
  expect(buildScript.existsSync(), isTrue, reason: 'Missing $appDir/build.sh');

  final result = await Process.run(
    '/bin/sh',
    ['./build.sh'],
    workingDirectory: appDir,
    environment: environment,
  );
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
}

Future<Process> startFixture(
  String appDir, {
  Map<String, String>? environment,
}) async {
  final runScript = File('$appDir/run.sh');
  expect(runScript.existsSync(), isTrue, reason: 'Missing $appDir/run.sh');

  final process = await Process.start(
    '/bin/sh',
    ['./run.sh'],
    workingDirectory: appDir,
    environment: environment,
  );
  attachProcessCleanup(process);
  return process;
}

void attachProcessCleanup(
  Process process, {
  Duration timeout = const Duration(seconds: 3),
}) {
  addTearDown(() async {
    if (process.kill(ProcessSignal.sigterm)) {
      await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
  });
}

Stream<String> stdoutLines(Process process) {
  return process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();
}

Future<String> waitForLinePrefix(
  Stream<String> lines,
  String prefix, {
  Duration timeout = const Duration(seconds: 10),
  String? reason,
}) async {
  await for (final line in lines.timeout(timeout)) {
    if (line.startsWith(prefix)) {
      return line.substring(prefix.length);
    }
  }

  throw StateError(
    reason ?? 'Process did not print a line starting with $prefix',
  );
}

Future<Uri> waitForRuntimeUrl(
  Stream<String> lines, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final value = await waitForLinePrefix(
    lines,
    'URL:',
    timeout: timeout,
    reason: 'Runtime did not print a startup URL.',
  );
  return Uri.parse(value);
}

Future<HttpClientResponse> send(
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

Future<int> pickPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<void> waitForHttpServer(
  Uri uri, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(deadline)) {
    try {
      final response = await send(uri).timeout(const Duration(seconds: 2));
      await response.drain<void>();
      return;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  throw StateError('HTTP server did not become ready at $uri');
}
