import 'dart:io';

import 'package:args/args.dart';
import 'package:osrv/osrv.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('requests', defaultsTo: '200')
    ..addOption('max-overhead', defaultsTo: '0.05');

  final parsed = parser.parse(args);
  final requestCount = int.parse(parsed['requests'] as String);
  final maxOverhead = double.parse(parsed['max-overhead'] as String);

  final baseline = await _measureBaseline(requestCount);
  final osrv = await _measureOsrv(requestCount);

  final overhead = (osrv.p95Micros - baseline.p95Micros) / baseline.p95Micros;

  stdout.writeln('baseline p95: ${baseline.p95Micros}us');
  stdout.writeln('osrv p95: ${osrv.p95Micros}us');
  stdout.writeln('overhead: ${(overhead * 100).toStringAsFixed(2)}%');

  if (overhead > maxOverhead) {
    stderr.writeln(
      'Benchmark failed: overhead ${(overhead * 100).toStringAsFixed(2)}% '
      'exceeds ${(maxOverhead * 100).toStringAsFixed(2)}%.',
    );
    exitCode = 1;
  }
}

Future<_BenchResult> _measureBaseline(int requests) async {
  final server = await HttpServer.bind('127.0.0.1', 0, shared: false);
  server.listen((request) {
    request.response
      ..statusCode = 200
      ..write('ok');
    request.response.close();
  });

  try {
    final p95 = await _runLoad('http://127.0.0.1:${server.port}', requests);
    return _BenchResult(p95Micros: p95);
  } finally {
    await server.close(force: true);
  }
}

Future<_BenchResult> _measureOsrv(int requests) async {
  final server = Server(
    fetch: (request) => Response.text('ok'),
    hostname: '127.0.0.1',
    port: 0,
    silent: true,
  );
  await server.serve();

  try {
    final p95 = await _runLoad(server.url!, requests);
    return _BenchResult(p95Micros: p95);
  } finally {
    await server.close(force: true);
  }
}

Future<int> _runLoad(String baseUrl, int requests) async {
  final client = HttpClient();
  final samples = <int>[];
  try {
    for (var i = 0; i < requests; i++) {
      final watch = Stopwatch()..start();
      final req = await client.getUrl(Uri.parse(baseUrl));
      final res = await req.close();
      await res.drain<void>();
      watch.stop();
      samples.add(watch.elapsedMicroseconds);
    }
  } finally {
    client.close(force: true);
  }

  samples.sort();
  final index = (samples.length * 0.95).ceil() - 1;
  return samples[index.clamp(0, samples.length - 1)];
}

final class _BenchResult {
  const _BenchResult({required this.p95Micros});

  final int p95Micros;
}
