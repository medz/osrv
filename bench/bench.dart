import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:osrv/build.dart';

final Uint8List _postBodyBytes = Uint8List.fromList(
  utf8.encode(
    jsonEncode(<String, Object?>{
      'message': 'hello',
      'count': 1,
      'items': <int>[1, 2, 3],
    }),
  ),
);

final _scenarios = <_Scenario>[
  const _Scenario(
    id: 'get-text',
    method: 'GET',
    path: '/text',
    headers: <String, String>{},
    body: null,
  ),
  _Scenario(
    id: 'post-json',
    method: 'POST',
    path: '/json',
    headers: const <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
    },
    body: _postBodyBytes,
  ),
];

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show usage information.',
    )
    ..addOption('requests', defaultsTo: '200')
    ..addOption('warmup-requests', defaultsTo: '80')
    ..addOption('concurrency', defaultsTo: '12')
    ..addOption('min-runs', defaultsTo: '3')
    ..addOption('max-runs', defaultsTo: '8')
    ..addOption('max-overhead', defaultsTo: '0.05')
    ..addOption('target-filter', defaultsTo: '')
    ..addOption('scenario-filter', defaultsTo: '')
    ..addFlag('verbose', defaultsTo: false)
    ..addOption('batch-size', hide: true, defaultsTo: '200')
    ..addOption('warmup-batch-size', hide: true, defaultsTo: '80');

  late final _BenchConfig config;
  late final ArgResults parsed;
  try {
    parsed = parser.parse(args);
    if (parsed['help'] as bool) {
      stdout.writeln('Usage: dart run bench.dart [options]');
      stdout.writeln(parser.usage);
      return;
    }

    final minRuns = _parseInt(parsed, 'min-runs', min: 1);
    final maxRuns = _parseInt(parsed, 'max-runs', min: minRuns);
    config = _BenchConfig(
      requests: _parseIntWithFallback(
        parsed,
        preferred: 'requests',
        fallback: 'batch-size',
        min: 1,
      ),
      warmupRequests: _parseIntWithFallback(
        parsed,
        preferred: 'warmup-requests',
        fallback: 'warmup-batch-size',
        min: 1,
      ),
      concurrency: _parseInt(parsed, 'concurrency', min: 1),
      minRuns: minRuns,
      maxRuns: maxRuns,
      maxOverhead: _parseDouble(parsed, 'max-overhead', min: 0),
      targetFilter: _parsePattern(parsed['target-filter'] as String),
      scenarioFilter: _parsePattern(parsed['scenario-filter'] as String),
      verbose: parsed['verbose'] as bool,
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  final prepared = await _prepareTargets(verbose: config.verbose);
  if (prepared.targets.isEmpty) {
    stderr.writeln('No runnable targets found.');
    for (final skip in prepared.skipped) {
      stderr.writeln('- $skip');
    }
    exitCode = 1;
    return;
  }

  final selectedTargets = prepared.targets
      .where((target) => config.targetFilter?.hasMatch(target.id) ?? true)
      .toList();
  final selectedScenarios = _scenarios
      .where((scenario) => config.scenarioFilter?.hasMatch(scenario.id) ?? true)
      .toList();

  if (selectedTargets.isEmpty) {
    stderr.writeln('No targets match --target-filter.');
    exitCode = 1;
    return;
  }
  if (selectedScenarios.isEmpty) {
    stderr.writeln('No scenarios match --scenario-filter.');
    exitCode = 1;
    return;
  }

  stdout.writeln('Targets: ${selectedTargets.map((e) => e.id).join(', ')}');
  stdout.writeln('Scenarios: ${selectedScenarios.map((e) => e.id).join(', ')}');
  stdout.writeln(
    'Config: requests=${config.requests}, warmup=${config.warmupRequests}, '
    'concurrency=${config.concurrency}, runs=${config.minRuns}-${config.maxRuns}, '
    'max-overhead=${(config.maxOverhead * 100).toStringAsFixed(2)}%',
  );
  if (prepared.skipped.isNotEmpty) {
    stdout.writeln('Skipped targets:');
    for (final skip in prepared.skipped) {
      stdout.writeln('- $skip');
    }
  }
  stdout.writeln('');

  final rows = <_BenchRow>[];
  final failedTargets = <String, String>{};

  for (final target in selectedTargets) {
    for (final scenario in selectedScenarios) {
      final runLabel = '${target.id}/${scenario.id}';
      stdout.writeln('Running $runLabel ...');
      final samples = <double>[];
      var stable = false;
      var overhead = double.infinity;
      try {
        for (var i = 0; i < config.maxRuns; i++) {
          final benchmark = _HttpServerBenchmark(
            target: target,
            scenario: scenario,
            batchSize: config.requests,
            warmupBatchSize: config.warmupRequests,
            concurrency: config.concurrency,
            verbose: config.verbose,
          );
          final microsPerExercise = await benchmark.measure();
          final microsPerRequest = microsPerExercise / config.requests;
          samples.add(microsPerRequest);

          if (samples.length >= config.minRuns) {
            overhead = _relativeOverhead(samples);
            if (overhead <= config.maxOverhead) {
              stable = true;
              break;
            }
          }
        }

        final medianMicrosPerRequest = _median(samples);
        final requestsPerSecond = 1000000 / medianMicrosPerRequest;

        rows.add(
          _BenchRow(
            target: target.id,
            scenario: scenario.id,
            microsPerRequest: medianMicrosPerRequest,
            requestsPerSecond: requestsPerSecond,
            runs: samples.length,
            overhead: overhead.isFinite ? overhead : 0,
            stable: stable,
          ),
        );

        stdout.writeln(
          '  ${medianMicrosPerRequest.toStringAsFixed(2)} us/req, '
          '${requestsPerSecond.toStringAsFixed(2)} req/s '
          '(runs=${samples.length}, overhead=${((overhead.isFinite ? overhead : 0) * 100).toStringAsFixed(2)}%, stable=${stable ? 'yes' : 'no'})',
        );
      } catch (error, stackTrace) {
        final summary = _singleLine(error);
        failedTargets[target.id] = '${scenario.id}: $summary';
        stdout.writeln('  failed: $summary');
        if (config.verbose) {
          stderr.writeln(stackTrace);
        }
        break;
      }
    }
  }

  if (rows.isEmpty) {
    stderr.writeln('No successful benchmark runs.');
    if (failedTargets.isNotEmpty) {
      stderr.writeln('Failed targets:');
      for (final entry in failedTargets.entries) {
        stderr.writeln('- ${entry.key}: ${entry.value}');
      }
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('');
  _printMatrix(rows: rows, scenarios: selectedScenarios);
  if (failedTargets.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Failed targets:');
    for (final entry in failedTargets.entries) {
      stdout.writeln('- ${entry.key}: ${entry.value}');
    }
  }
}

Future<_PreparedTargets> _prepareTargets({required bool verbose}) async {
  final targets = <_Target>[
    _Target.vm(name: 'osrv', entry: 'fixtures/osrv.dart'),
    _Target.vm(name: 'shelf', entry: 'fixtures/shelf.dart'),
    _Target.vm(name: 'relic', entry: 'fixtures/relic.dart'),
  ];
  final skipped = <String>[];

  final artifactsDir = '.bench_artifacts';
  Directory(artifactsDir).createSync(recursive: true);

  BuildResult? osrvBuild;
  try {
    osrvBuild = await build(
      BuildOptions(
        entry: 'fixtures/osrv.dart',
        outDir: _join(artifactsDir, 'osrv'),
        silent: !verbose,
        workingDirectory: Directory.current.path,
        defaultEntry: 'fixtures/osrv.dart',
        fallbackEntry: 'fixtures/osrv.dart',
      ),
      logger: verbose ? stdout.writeln : null,
    );
  } catch (error) {
    skipped.add('osrv(native/node/bun/deno): build failed ($error)');
  }

  if (osrvBuild != null) {
    targets.add(
      _Target.native(name: 'osrv', executable: osrvBuild.executablePath),
    );

    final nodeEntry = _joinAll(<String>[
      osrvBuild.outDir,
      'js',
      'node',
      'index.mjs',
    ]);
    final bunEntry = _joinAll(<String>[
      osrvBuild.outDir,
      'js',
      'bun',
      'index.mjs',
    ]);
    final denoEntry = _joinAll(<String>[
      osrvBuild.outDir,
      'js',
      'deno',
      'index.mjs',
    ]);

    if (await _hasCommand('node')) {
      targets.add(
        _Target.custom(
          id: 'osrv(node)',
          executable: 'node',
          arguments: <String>[nodeEntry],
          supportsPortArgument: false,
          fixedPort: 3000,
        ),
      );
    } else {
      skipped.add('osrv(node): `node` not found');
    }

    if (await _hasCommand('bun')) {
      targets.add(
        _Target.custom(
          id: 'osrv(bun)',
          executable: 'bun',
          arguments: <String>[bunEntry],
          supportsPortArgument: false,
          fixedPort: 3000,
        ),
      );
    } else {
      skipped.add('osrv(bun): `bun` not found');
    }

    if (await _hasCommand('deno')) {
      targets.add(
        _Target.custom(
          id: 'osrv(deno)',
          executable: 'deno',
          arguments: <String>[
            'run',
            '--allow-net',
            '--allow-env',
            '--allow-read',
            denoEntry,
          ],
          supportsPortArgument: false,
          fixedPort: 3000,
        ),
      );
    } else {
      skipped.add('osrv(deno): `deno` not found');
    }
  }

  final shelfNative = await _compileNative(
    source: 'fixtures/shelf.dart',
    output: _joinAll(<String>[
      artifactsDir,
      'shelf',
      _exeName('shelf_fixture'),
    ]),
    verbose: verbose,
  );
  if (shelfNative == null) {
    skipped.add('shelf(native): compile failed');
  } else {
    targets.add(_Target.native(name: 'shelf', executable: shelfNative));
  }

  final relicNative = await _compileNative(
    source: 'fixtures/relic.dart',
    output: _joinAll(<String>[
      artifactsDir,
      'relic',
      _exeName('relic_fixture'),
    ]),
    verbose: verbose,
  );
  if (relicNative == null) {
    skipped.add('relic(native): compile failed');
  } else {
    targets.add(_Target.native(name: 'relic', executable: relicNative));
  }

  return _PreparedTargets(targets: targets, skipped: skipped);
}

Future<String?> _compileNative({
  required String source,
  required String output,
  required bool verbose,
}) async {
  final outputFile = File(output)..parent.createSync(recursive: true);
  final result = await Process.run('dart', <String>[
    'compile',
    'exe',
    source,
    '-o',
    outputFile.path,
  ], workingDirectory: Directory.current.path);
  if (result.exitCode == 0) {
    return outputFile.path;
  }
  if (verbose) {
    stderr.writeln(
      'native compile failed for $source\n${result.stdout}\n${result.stderr}',
    );
  }
  return null;
}

Future<bool> _hasCommand(String command) async {
  try {
    final result = await Process.run(command, <String>['--version']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void _printMatrix({
  required List<_BenchRow> rows,
  required List<_Scenario> scenarios,
}) {
  final byTarget = <String, Map<String, _BenchRow>>{};
  for (final row in rows) {
    byTarget.putIfAbsent(
      row.target,
      () => <String, _BenchRow>{},
    )[row.scenario] = row;
  }

  final headers = <String>['target'];
  for (final scenario in scenarios) {
    headers.add('${scenario.id} us/req');
    headers.add('${scenario.id} req/s');
  }
  stdout.writeln('| ${headers.join(' | ')} |');
  stdout.writeln(
    '| ${List<String>.filled(headers.length, '---').join(' | ')} |',
  );

  final sortedTargets = byTarget.keys.toList()..sort();
  for (final target in sortedTargets) {
    final values = <String>[target];
    final map = byTarget[target]!;
    for (final scenario in scenarios) {
      final row = map[scenario.id];
      if (row == null) {
        values.add('-');
        values.add('-');
        continue;
      }
      values.add(row.microsPerRequest.toStringAsFixed(2));
      values.add(row.requestsPerSecond.toStringAsFixed(2));
    }
    stdout.writeln('| ${values.join(' | ')} |');
  }
}

int _parseInt(ArgResults parsed, String name, {required int min}) {
  final raw = parsed[name] as String;
  final value = int.tryParse(raw);
  if (value == null || value < min) {
    throw FormatException('--$name must be an integer >= $min');
  }
  return value;
}

int _parseIntWithFallback(
  ArgResults parsed, {
  required String preferred,
  required String fallback,
  required int min,
}) {
  final option = (!parsed.wasParsed(preferred) && parsed.wasParsed(fallback))
      ? fallback
      : preferred;
  return _parseInt(parsed, option, min: min);
}

double _parseDouble(ArgResults parsed, String name, {required double min}) {
  final raw = parsed[name] as String;
  final value = double.tryParse(raw);
  if (value == null || value < min) {
    throw FormatException('--$name must be a number >= $min');
  }
  return value;
}

RegExp? _parsePattern(String raw) {
  if (raw.trim().isEmpty) {
    return null;
  }
  return RegExp(raw);
}

Future<int> _pickFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  try {
    return socket.port;
  } finally {
    await socket.close();
  }
}

Future<bool> _isPortAvailable(int port) async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}

String _join(String left, String right) =>
    '$left${Platform.pathSeparator}$right';

String _joinAll(List<String> parts) {
  return parts.join(Platform.pathSeparator);
}

String _exeName(String base) => Platform.isWindows ? '$base.exe' : base;

String _singleLine(Object value) {
  final text = '$value'.trim();
  final index = text.indexOf('\n');
  if (index < 0) {
    return text;
  }
  return text.substring(0, index);
}

double _median(List<double> values) {
  if (values.isEmpty) {
    throw StateError('No samples to compute median.');
  }
  final sorted = values.toList()..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[middle];
  }
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

double _relativeOverhead(List<double> values) {
  if (values.length < 2) {
    return 0;
  }
  final minValue = values.reduce(math.min);
  final maxValue = values.reduce(math.max);
  final medianValue = _median(values);
  if (medianValue == 0) {
    return 0;
  }
  return (maxValue - minValue) / medianValue;
}

final class _HttpServerBenchmark extends AsyncBenchmarkBase {
  _HttpServerBenchmark({
    required this.target,
    required this.scenario,
    required this.batchSize,
    required this.warmupBatchSize,
    required this.concurrency,
    required this.verbose,
  }) : super('${target.id}/${scenario.id}');

  final _Target target;
  final _Scenario scenario;
  final int batchSize;
  final int warmupBatchSize;
  final int concurrency;
  final bool verbose;

  late Process _process;
  late HttpClient _client;
  late Uri _baseUri;

  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  final List<String> _logs = <String>[];
  int? _exitCode;

  @override
  Future<void> setup() async {
    final port = target.fixedPort ?? await _pickFreePort();
    if (target.fixedPort != null && !await _isPortAvailable(port)) {
      throw StateError(
        '${target.id} requires fixed port $port, but it is not available.',
      );
    }
    _baseUri = Uri.parse('http://127.0.0.1:$port');
    _client = HttpClient()..maxConnectionsPerHost = concurrency;

    final env = <String, String>{
      ...Platform.environment,
      ...target.environment,
      'PORT': '$port',
      'HOSTNAME': '127.0.0.1',
    };
    final launchArgs = <String>[...target.arguments];
    if (target.supportsPortArgument) {
      launchArgs.add('--port=$port');
    }
    _process = await Process.start(
      target.executable,
      launchArgs,
      workingDirectory: Directory.current.path,
      environment: env,
    );

    _stdoutSub = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _recordLog('stdout', line));
    _stderrSub = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _recordLog('stderr', line));
    unawaited(
      _process.exitCode.then((code) {
        _exitCode = code;
      }),
    );

    try {
      await _waitReady();
    } catch (_) {
      await _cleanupSetupFailure();
      rethrow;
    }
  }

  @override
  Future<void> warmup() => _runBatch(warmupBatchSize);

  @override
  Future<void> exercise() => _runBatch(batchSize);

  @override
  Future<void> teardown() async {
    _client.close(force: true);
    await _stopProcess();
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
  }

  Future<void> _waitReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    final uri = _baseUri.replace(path: '/text');

    while (DateTime.now().isBefore(deadline)) {
      if (_exitCode != null) {
        throw StateError(
          '${target.id} exited early with code $_exitCode\n${_logs.join('\n')}',
        );
      }
      try {
        final request = await _client.getUrl(uri);
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == 200) {
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    throw TimeoutException(
      'Timed out waiting for ${target.id} startup at $uri\n${_logs.join('\n')}',
    );
  }

  Future<void> _runBatch(int requests) async {
    final workers = math.min(concurrency, requests);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final current = next;
        next++;
        if (current >= requests) {
          return;
        }
        await _runSingle();
      }
    }

    await Future.wait(List<Future<void>>.generate(workers, (_) => worker()));
  }

  Future<void> _runSingle() async {
    final uri = _baseUri.replace(path: scenario.path);
    final request = await _client.openUrl(scenario.method, uri);
    scenario.headers.forEach(request.headers.set);
    final body = scenario.body;
    if (body != null) {
      request.contentLength = body.length;
      request.add(body);
    }
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode != 200) {
      throw HttpException(
        'Unexpected status ${response.statusCode} for ${scenario.method} ${scenario.path}',
        uri: uri,
      );
    }
  }

  Future<void> _stopProcess() async {
    if (_exitCode != null) {
      return;
    }
    _process.kill();
    try {
      await _process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
      await _process.exitCode.timeout(const Duration(seconds: 2));
    }
  }

  Future<void> _cleanupSetupFailure() async {
    _client.close(force: true);
    await _stopProcess();
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
  }

  void _recordLog(String stream, String line) {
    if (verbose) {
      stdout.writeln('[${target.id}][$stream] $line');
    }
    _logs.add('[$stream] $line');
    if (_logs.length > 80) {
      _logs.removeAt(0);
    }
  }
}

final class _Target {
  const _Target({
    required this.id,
    required this.executable,
    required this.arguments,
    this.environment = const <String, String>{},
    this.supportsPortArgument = true,
    this.fixedPort,
  });

  factory _Target.vm({required String name, required String entry}) {
    return _Target(
      id: '$name(vm)',
      executable: 'dart',
      arguments: <String>['run', entry],
    );
  }

  factory _Target.native({required String name, required String executable}) {
    return _Target(
      id: '$name(native)',
      executable: executable,
      arguments: const <String>[],
    );
  }

  factory _Target.custom({
    required String id,
    required String executable,
    required List<String> arguments,
    Map<String, String> environment = const <String, String>{},
    bool supportsPortArgument = true,
    int? fixedPort,
  }) {
    return _Target(
      id: id,
      executable: executable,
      arguments: arguments,
      environment: environment,
      supportsPortArgument: supportsPortArgument,
      fixedPort: fixedPort,
    );
  }

  final String id;
  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
  final bool supportsPortArgument;
  final int? fixedPort;
}

final class _Scenario {
  const _Scenario({
    required this.id,
    required this.method,
    required this.path,
    required this.headers,
    required this.body,
  });

  final String id;
  final String method;
  final String path;
  final Map<String, String> headers;
  final Uint8List? body;
}

final class _BenchConfig {
  const _BenchConfig({
    required this.requests,
    required this.warmupRequests,
    required this.concurrency,
    required this.minRuns,
    required this.maxRuns,
    required this.maxOverhead,
    required this.targetFilter,
    required this.scenarioFilter,
    required this.verbose,
  });

  final int requests;
  final int warmupRequests;
  final int concurrency;
  final int minRuns;
  final int maxRuns;
  final double maxOverhead;
  final RegExp? targetFilter;
  final RegExp? scenarioFilter;
  final bool verbose;
}

final class _PreparedTargets {
  const _PreparedTargets({required this.targets, required this.skipped});

  final List<_Target> targets;
  final List<String> skipped;
}

final class _BenchRow {
  const _BenchRow({
    required this.target,
    required this.scenario,
    required this.microsPerRequest,
    required this.requestsPerSecond,
    required this.runs,
    required this.overhead,
    required this.stable,
  });

  final String target;
  final String scenario;
  final double microsPerRequest;
  final double requestsPerSecond;
  final int runs;
  final double overhead;
  final bool stable;
}
