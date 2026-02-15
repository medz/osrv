import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  const exampleDir = 'example';
  await _run('dart', <String>[
    'run',
    'osrv',
    'build',
    '--silent',
  ], workingDirectory: exampleDir);

  final dartPort = await _findFreePort();
  final nodePort = await _findFreePort();
  final bunPort = await _findFreePort();
  final denoPort = await _findFreePort();

  final checks = <_RuntimeCheck>[
    _RuntimeCheck(
      name: 'dart',
      executable: 'dart',
      arguments: <String>[
        'run',
        'osrv',
        'serve',
        '--silent',
        '--port',
        '$dartPort',
        '--hostname',
        '127.0.0.1',
      ],
      url: 'http://127.0.0.1:$dartPort',
      workingDirectory: exampleDir,
    ),
    _RuntimeCheck(
      name: 'node',
      executable: 'node',
      arguments: <String>['dist/js/node/index.mjs'],
      url: 'http://127.0.0.1:$nodePort',
      workingDirectory: exampleDir,
      environment: <String, String>{
        'PORT': '$nodePort',
        'HOSTNAME': '127.0.0.1',
      },
    ),
    _RuntimeCheck(
      name: 'bun',
      executable: 'bun',
      arguments: <String>['run', 'dist/js/bun/index.mjs'],
      url: 'http://127.0.0.1:$bunPort',
      workingDirectory: exampleDir,
      environment: <String, String>{
        'PORT': '$bunPort',
        'HOSTNAME': '127.0.0.1',
      },
    ),
    _RuntimeCheck(
      name: 'deno',
      executable: 'deno',
      arguments: <String>['run', '-A', 'dist/js/deno/index.mjs'],
      url: 'http://127.0.0.1:$denoPort',
      workingDirectory: exampleDir,
      environment: <String, String>{
        'PORT': '$denoPort',
        'HOSTNAME': '127.0.0.1',
      },
    ),
  ];

  final available = <_RuntimeCheck>[];
  for (final check in checks) {
    if (await _isExecutableAvailable(check.executable)) {
      available.add(check);
    } else {
      stdout.writeln(
        '[contract] skip ${check.name}: `${check.executable}` not found',
      );
    }
  }

  if (available.isEmpty) {
    stderr.writeln('[contract] no runtimes available to test');
    exitCode = 1;
    return;
  }

  Map<String, Object?>? baseline;
  String? baselineName;

  for (final check in available) {
    final result = await _runContractForRuntime(check);
    stdout.writeln('[contract] ${check.name} => ${jsonEncode(result)}');

    if (baseline == null) {
      baseline = result;
      baselineName = check.name;
      continue;
    }

    final mismatch = _compareContract(baseline, result);
    if (mismatch != null) {
      stderr.writeln(
        '[contract] mismatch between $baselineName and ${check.name}: $mismatch',
      );
      exitCode = 1;
      return;
    }
  }

  stdout.writeln(
    '[contract] matrix passed for: ${available.map((e) => e.name).join(', ')}',
  );
}

Future<Map<String, Object?>> _runContractForRuntime(_RuntimeCheck check) async {
  Process? process;
  StreamSubscription<String>? stdoutSubscription;
  StreamSubscription<String>? stderrSubscription;
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();

  try {
    process = await Process.start(
      check.executable,
      check.arguments,
      workingDirectory: check.workingDirectory,
      environment: <String, String>{
        ...Platform.environment,
        ...?check.environment,
      },
    );

    stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .listen(stdoutBuffer.write, onError: (_) {});
    stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write, onError: (_) {});

    await _waitForServerReady(Uri.parse(check.url));

    final root = await _request(Uri.parse('${check.url}/'));
    final echo = await _request(
      Uri.parse('${check.url}/echo'),
      method: 'POST',
      body: 'hello',
    );
    final error = await _request(Uri.parse('${check.url}/error'));
    final wsEcho = await _webSocketEcho(
      Uri.parse('${check.url}/ws'),
      message: 'hello-ws',
    );

    final rootJson = jsonDecode(root.body) as Map<String, Object?>;
    final errorJson = jsonDecode(error.body) as Map<String, Object?>;

    return <String, Object?>{
      'root': <String, Object?>{
        'status': root.status,
        'ok': rootJson['ok'],
        'method': rootJson['method'],
        'path': rootJson['path'],
      },
      'echo': <String, Object?>{'status': echo.status, 'body': echo.body},
      'error': <String, Object?>{
        'status': error.status,
        'ok': errorJson['ok'],
        'error': errorJson['error'],
      },
      'ws': <String, Object?>{'echo': wsEcho},
    };
  } finally {
    if (process != null) {
      if (!process.kill(ProcessSignal.sigterm)) {
        process.kill();
      }
      await process.exitCode;
    }
    await stdoutSubscription?.cancel();
    await stderrSubscription?.cancel();

    final stderrText = stderrBuffer.toString().trim();
    if (stderrText.isNotEmpty) {
      stdout.writeln('[contract/${check.name}/stderr] $stderrText');
    }
  }
}

Future<String> _webSocketEcho(Uri url, {required String message}) async {
  final wsUri = Uri(
    scheme: url.scheme == 'https' ? 'wss' : 'ws',
    userInfo: url.userInfo,
    host: url.host,
    port: url.port,
    path: url.path,
    query: url.query,
  );

  final socket = await WebSocket.connect(wsUri.toString());
  try {
    socket.add(message);
    final response = await socket.first.timeout(const Duration(seconds: 5));
    if (response is String) {
      return response;
    }
    if (response is List<int>) {
      return utf8.decode(response, allowMalformed: true);
    }
    return response.toString();
  } finally {
    await socket.close();
  }
}

String? _compareContract(
  Map<String, Object?> left,
  Map<String, Object?> right,
) {
  final leftJson = jsonEncode(left);
  final rightJson = jsonEncode(right);
  if (leftJson == rightJson) {
    return null;
  }

  return 'left=$leftJson right=$rightJson';
}

Future<void> _waitForServerReady(Uri url) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      final result = await _request(url);
      if (result.status >= 200 && result.status < 600) {
        return;
      }
    } catch (error) {
      lastError = error;
    }

    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  throw StateError('Server did not become ready at $url. lastError=$lastError');
}

Future<bool> _isExecutableAvailable(String executable) async {
  try {
    final result = await Process.run('which', <String>[executable]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<int> _findFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  try {
    return socket.port;
  } finally {
    await socket.close();
  }
}

Future<_HttpResult> _request(
  Uri url, {
  String method = 'GET',
  String? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, url);
    if (body != null) {
      request.write(body);
    }
    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);
    return _HttpResult(response.statusCode, responseBody);
  } finally {
    client.close(force: true);
  }
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: Platform.environment,
    runInShell: false,
  );

  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      'exit=${result.exitCode}\nstdout=${result.stdout}\nstderr=${result.stderr}',
      result.exitCode,
    );
  }
}

final class _RuntimeCheck {
  const _RuntimeCheck({
    required this.name,
    required this.executable,
    required this.arguments,
    required this.url,
    required this.workingDirectory,
    this.environment,
  });

  final String name;
  final String executable;
  final List<String> arguments;
  final String url;
  final String workingDirectory;
  final Map<String, String>? environment;
}

final class _HttpResult {
  const _HttpResult(this.status, this.body);

  final int status;
  final String body;
}
