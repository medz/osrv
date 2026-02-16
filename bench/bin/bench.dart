import 'dart:io';
import 'dart:math' as math;

import 'package:args/args.dart';
import 'package:osrv/osrv.dart' as osrv;
import 'package:relic/relic.dart' as relic;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

const _baselineScenario = 'baseline';
const _gateScenario = 'osrv';
const _comparisonScenarios = <String>['osrv', 'shelf', 'relic'];

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('requests', defaultsTo: '200')
    ..addOption('warmup', defaultsTo: '50')
    ..addOption('rounds', defaultsTo: '7')
    ..addOption('burn-in-rounds', defaultsTo: '2')
    ..addOption('concurrency', defaultsTo: '8')
    ..addOption('max-overhead', defaultsTo: '0.05');

  late final _BenchConfig config;
  try {
    final parsed = parser.parse(args);
    config = _BenchConfig(
      requests: _parseInt(parsed, 'requests', min: 1),
      warmup: _parseInt(parsed, 'warmup', min: 0),
      rounds: _parseInt(parsed, 'rounds', min: 1),
      burnInRounds: _parseInt(parsed, 'burn-in-rounds', min: 0),
      concurrency: _parseInt(parsed, 'concurrency', min: 1),
      maxOverhead: _parseDouble(parsed, 'max-overhead', min: 0),
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  final scenarios = <_ScenarioDescriptor>[
    _ScenarioDescriptor(name: _baselineScenario, start: _startBaselineServer),
    _ScenarioDescriptor(name: _gateScenario, start: _startOsrvServer),
    _ScenarioDescriptor(name: 'shelf', start: _startShelfServer),
    _ScenarioDescriptor(name: 'relic', start: _startRelicServer),
  ];
  final scenarioNames = scenarios.map((scenario) => scenario.name).toList();

  final running = <String, _BoundServer>{};
  try {
    for (final scenario in scenarios) {
      running[scenario.name] = await scenario.start();
    }

    final uriByScenario = <String, Uri>{
      for (final entry in running.entries) entry.key: entry.value.uri,
    };

    for (var i = 0; i < config.burnInRounds; i++) {
      await _runRound(
        uriByScenario: uriByScenario,
        config: config,
        order: _roundOrder(scenarioNames, i),
      );
      stdout.writeln('burn-in ${i + 1}/${config.burnInRounds} complete');
    }

    final rounds = <_RoundResult>[];
    final allSamples = <String, List<int>>{
      for (final name in scenarioNames) name: <int>[],
    };

    for (var i = 0; i < config.rounds; i++) {
      final round = await _runRound(
        uriByScenario: uriByScenario,
        config: config,
        order: _roundOrder(scenarioNames, i),
      );
      rounds.add(round);
      for (final name in scenarioNames) {
        allSamples[name]!.addAll(round.results[name]!.samples);
      }

      stdout.writeln(_formatRoundLine(i + 1, config.rounds, round));
    }

    final aggregateP95 = <String, int>{
      for (final name in scenarioNames)
        name: _percentileInt(allSamples[name]!, 0.95),
    };

    final medianRoundOverhead = <String, double>{
      for (final name in _comparisonScenarios)
        name: _percentileDouble(
          rounds
              .map((round) => round.overheadToBaseline(name))
              .whereType<double>()
              .toList(),
          0.5,
        ),
    };

    stdout.writeln('');
    stdout.writeln('aggregate p95:');
    for (final name in scenarioNames) {
      stdout.writeln('  $name: ${aggregateP95[name]}us');
    }

    stdout.writeln('aggregate overhead vs baseline:');
    for (final name in _comparisonScenarios) {
      final overhead = _overhead(
        baselineMicros: aggregateP95[_baselineScenario]!,
        targetMicros: aggregateP95[name]!,
      );
      stdout.writeln('  $name: ${_formatPercent(overhead)}');
    }

    stdout.writeln('median round overhead vs baseline:');
    for (final name in _comparisonScenarios) {
      stdout.writeln('  $name: ${_formatPercent(medianRoundOverhead[name]!)}');
    }

    if (medianRoundOverhead[_gateScenario]! > config.maxOverhead) {
      stderr.writeln(
        'Benchmark failed: median round overhead for $_gateScenario '
        '${_formatPercent(medianRoundOverhead[_gateScenario]!)} '
        'exceeds ${_formatPercent(config.maxOverhead)}.',
      );
      exitCode = 1;
    }
  } finally {
    for (final server in running.values) {
      await server.close();
    }
  }
}

List<String> _roundOrder(List<String> names, int roundIndex) {
  final rotated = List<String>.generate(
    names.length,
    (index) => names[(index + roundIndex) % names.length],
  );
  if (roundIndex.isOdd) {
    return rotated.reversed.toList();
  }
  return rotated;
}

String _formatRoundLine(int round, int total, _RoundResult result) {
  final baselineP95 = result.results[_baselineScenario]!.p95Micros;
  final parts = <String>['baseline p95 ${baselineP95}us'];

  for (final scenario in _comparisonScenarios) {
    final scenarioP95 = result.results[scenario]!.p95Micros;
    final overhead = result.overheadToBaseline(scenario)!;
    parts.add(
      '$scenario p95 ${scenarioP95}us (overhead ${_formatPercent(overhead)})',
    );
  }

  return 'round $round/$total: ${parts.join(', ')}';
}

Future<_RoundResult> _runRound({
  required Map<String, Uri> uriByScenario,
  required _BenchConfig config,
  required List<String> order,
}) async {
  final results = <String, _ScenarioResult>{};
  for (final name in order) {
    results[name] = await _runScenario(uriByScenario[name]!, config);
  }
  return _RoundResult(results);
}

Future<_ScenarioResult> _runScenario(Uri uri, _BenchConfig config) async {
  final client = HttpClient()..maxConnectionsPerHost = config.concurrency;
  try {
    await _runLoad(
      client: client,
      uri: uri,
      requests: config.warmup,
      concurrency: config.concurrency,
      collectSamples: false,
    );
    final samples = await _runLoad(
      client: client,
      uri: uri,
      requests: config.requests,
      concurrency: config.concurrency,
      collectSamples: true,
    );
    return _ScenarioResult(samples);
  } finally {
    client.close(force: true);
  }
}

Future<List<int>> _runLoad({
  required HttpClient client,
  required Uri uri,
  required int requests,
  required int concurrency,
  required bool collectSamples,
}) async {
  if (requests == 0) {
    return const <int>[];
  }

  final workerCount = math.min(concurrency, requests);
  final samples = collectSamples ? List<int>.filled(requests, 0) : <int>[];
  var nextIndex = 0;

  Future<void> worker() async {
    while (true) {
      final index = nextIndex;
      nextIndex++;
      if (index >= requests) {
        return;
      }

      final watch = collectSamples ? (Stopwatch()..start()) : null;
      final request = await client.getUrl(uri);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Unexpected status code ${response.statusCode}',
          uri: uri,
        );
      }

      if (watch case final Stopwatch stopwatch) {
        stopwatch.stop();
        samples[index] = stopwatch.elapsedMicroseconds;
      }
    }
  }

  await Future.wait(List<Future<void>>.generate(workerCount, (_) => worker()));
  return samples;
}

Future<_BoundServer> _startBaselineServer() async {
  final server = await HttpServer.bind('127.0.0.1', 0, shared: false);
  server.listen((request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..write('ok');
    await request.response.close();
  });

  return _BoundServer(
    uri: Uri.parse('http://127.0.0.1:${server.port}'),
    close: () => server.close(force: true),
  );
}

Future<_BoundServer> _startOsrvServer() async {
  final server = osrv.Server(
    fetch: (_) => osrv.Response.text('ok'),
    hostname: '127.0.0.1',
    port: 0,
    silent: true,
  );
  await server.serve();

  return _BoundServer(
    uri: Uri.parse(server.url!),
    close: () => server.close(force: true),
  );
}

Future<_BoundServer> _startShelfServer() async {
  final handler = const shelf.Pipeline().addHandler(
    (_) => shelf.Response.ok('ok'),
  );
  final server = await shelf_io.serve(handler, '127.0.0.1', 0, shared: false);

  return _BoundServer(
    uri: Uri.parse('http://127.0.0.1:${server.port}'),
    close: () => server.close(force: true),
  );
}

Future<_BoundServer> _startRelicServer() async {
  final handler = const relic.Pipeline().addHandler(
    (_) => relic.Response.ok(body: relic.Body.fromString('ok')),
  );
  final server = relic.RelicServer(
    () => relic.IOAdapter.bind(InternetAddress.loopbackIPv4, port: 0),
  );
  await server.mountAndStart(handler);

  return _BoundServer(
    uri: Uri.parse('http://127.0.0.1:${server.port}'),
    close: () => server.close(force: true),
  );
}

int _parseInt(ArgResults parsed, String name, {required int min}) {
  final raw = parsed[name] as String;
  final value = int.tryParse(raw);
  if (value == null || value < min) {
    throw FormatException('--$name must be an integer >= $min.');
  }
  return value;
}

double _parseDouble(ArgResults parsed, String name, {required double min}) {
  final raw = parsed[name] as String;
  final value = double.tryParse(raw);
  if (value == null || value < min) {
    throw FormatException('--$name must be a number >= $min.');
  }
  return value;
}

int _percentileInt(List<int> values, double percentile) {
  if (values.isEmpty) {
    throw StateError('Cannot compute percentile for empty input.');
  }

  final sorted = List<int>.from(values)..sort();
  final index = ((sorted.length * percentile).ceil() - 1).clamp(
    0,
    sorted.length - 1,
  );
  return sorted[index];
}

double _percentileDouble(List<double> values, double percentile) {
  if (values.isEmpty) {
    throw StateError('Cannot compute percentile for empty input.');
  }

  final sorted = List<double>.from(values)..sort();
  final index = ((sorted.length * percentile).ceil() - 1).clamp(
    0,
    sorted.length - 1,
  );
  return sorted[index];
}

double _overhead({required int baselineMicros, required int targetMicros}) {
  if (baselineMicros <= 0) {
    throw StateError('Baseline latency must be positive.');
  }
  return (targetMicros - baselineMicros) / baselineMicros;
}

String _formatPercent(double value) => '${(value * 100).toStringAsFixed(2)}%';

final class _BenchConfig {
  const _BenchConfig({
    required this.requests,
    required this.warmup,
    required this.rounds,
    required this.burnInRounds,
    required this.concurrency,
    required this.maxOverhead,
  });

  final int requests;
  final int warmup;
  final int rounds;
  final int burnInRounds;
  final int concurrency;
  final double maxOverhead;
}

final class _ScenarioDescriptor {
  const _ScenarioDescriptor({required this.name, required this.start});

  final String name;
  final Future<_BoundServer> Function() start;
}

final class _RoundResult {
  const _RoundResult(this.results);

  final Map<String, _ScenarioResult> results;

  double? overheadToBaseline(String scenario) {
    final baseline = results[_baselineScenario];
    final target = results[scenario];
    if (baseline == null || target == null) {
      return null;
    }
    return _overhead(
      baselineMicros: baseline.p95Micros,
      targetMicros: target.p95Micros,
    );
  }
}

final class _ScenarioResult {
  _ScenarioResult(this.samples) : p95Micros = _percentileInt(samples, 0.95);

  final List<int> samples;
  final int p95Micros;
}

final class _BoundServer {
  const _BoundServer({required this.uri, required this.close});

  final Uri uri;
  final Future<void> Function() close;
}
