import 'dart:io';

import 'package:osrv/build.dart' as osrv_build;

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == 'help' || args.first == '--help') {
    _printUsage();
    return;
  }

  final command = args.first;
  final commandArgs = args.sublist(1);

  switch (command) {
    case 'serve':
      await _serve(commandArgs);
    case 'build':
      await _build(commandArgs);
    default:
      stderr.writeln('Unknown command: $command');
      _printUsage();
      exitCode = 64;
  }
}

Future<void> _serve(List<String> args) async {
  final entry = _resolveEntry(_readOption(args, '--entry') ?? 'server.dart');
  if (entry == null) {
    stderr.writeln('Unable to find server entrypoint.');
    stderr.writeln('Tried --entry value and bin/server.dart');
    exitCode = 64;
    return;
  }

  final passthrough = _collectPassthroughArgs(args);
  final process = await Process.start(Platform.resolvedExecutable, <String>[
    'run',
    entry,
    ...passthrough,
  ], mode: ProcessStartMode.inheritStdio);

  exitCode = await process.exitCode;
}

Future<void> _build(List<String> args) async {
  final entryOption = _readOption(args, '--entry') ?? 'server.dart';
  final outDir = _readOption(args, '--out-dir') ?? 'dist';
  final silent = args.contains('--silent');

  final resolvedEntry = _resolveEntry(entryOption);
  if (resolvedEntry == null) {
    stderr.writeln('Unable to find build entrypoint.');
    stderr.writeln('Tried --entry value and bin/server.dart');
    exitCode = 64;
    return;
  }

  try {
    final result = await osrv_build.build(
      osrv_build.BuildOptions(
        entry: resolvedEntry,
        outDir: outDir,
        silent: silent,
        workingDirectory: Directory.current.path,
      ),
      logger: silent ? null : stdout.writeln,
    );

    if (!silent) {
      stdout.writeln('build out: ${result.outDir}');
      for (final entry in result.artifacts.entries) {
        stdout.writeln('${entry.key}: ${entry.value}');
      }
    }
  } catch (error) {
    stderr.writeln('Build failed: $error');
    exitCode = 1;
  }
}

String? _readOption(List<String> args, String name) {
  for (final arg in args) {
    if (arg.startsWith('$name=')) {
      return arg.substring(name.length + 1);
    }
  }
  return null;
}

List<String> _collectPassthroughArgs(List<String> args) {
  final separator = args.indexOf('--');
  if (separator < 0 || separator == args.length - 1) {
    return const <String>[];
  }
  return args.sublist(separator + 1);
}

String? _resolveEntry(String entry) {
  final preferred = File(entry);
  if (preferred.existsSync()) {
    return entry;
  }

  const fallback = 'bin/server.dart';
  if (File(fallback).existsSync()) {
    return fallback;
  }

  return null;
}

void _printUsage() {
  stdout.writeln('osrv CLI');
  stdout.writeln('');
  stdout.writeln('Commands:');
  stdout.writeln('  osrv serve [--entry=server.dart] [-- ...args]');
  stdout.writeln(
    '  osrv build [--entry=server.dart] [--out-dir=dist] [--silent]',
  );
}
