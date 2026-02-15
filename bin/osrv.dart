import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:osrv/build.dart';

const String _defaultEntry = 'server.dart';
const String _defaultFallbackEntry = 'bin/server.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addCommand('serve')
    ..addCommand('build');

  parser.commands['serve']!
    ..addOption(
      'entry',
      defaultsTo: _defaultEntry,
      help: 'Dart entry file. Defaults to `server.dart`.',
    )
    ..addOption('port', help: 'Port to listen on.')
    ..addOption('hostname', help: 'Hostname to bind to.')
    ..addOption(
      'protocol',
      allowed: <String>['http', 'https'],
      help: 'Protocol preference.',
    )
    ..addFlag('silent', defaultsTo: false, help: 'Silence osrv CLI logs.');

  parser.commands['build']!
    ..addOption(
      'entry',
      defaultsTo: _defaultEntry,
      help: 'Dart entry file to compile. Defaults to `server.dart`.',
    )
    ..addOption('out-dir', defaultsTo: 'dist', help: 'Build output directory.')
    ..addFlag(
      'silent',
      defaultsTo: false,
      help: 'Silence build progress logs.',
    );

  ArgResults result;
  try {
    result = parser.parse(args);
  } on FormatException catch (error) {
    stderr.writeln('[osrv] ${error.message}');
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  final command = result.command;
  if (command == null) {
    stdout.writeln('osrv commands:');
    stdout.writeln(parser.usage);
    return;
  }

  switch (command.name) {
    case 'serve':
      await _runServe(command);
      return;
    case 'build':
      await _runBuild(command);
      return;
    default:
      stderr.writeln('[osrv] unknown command: ${command.name}');
      exitCode = 64;
      return;
  }
}

Future<void> _runServe(ArgResults command) async {
  final requestedEntry = command['entry'] as String;
  final entry = resolveEntry(
    requestedEntry,
    defaultEntry: _defaultEntry,
    fallbackEntry: _defaultFallbackEntry,
  );
  if (entry == null) {
    stderr.writeln(
      '[osrv] entry not found. looked for `$requestedEntry` '
      'and fallback `$_defaultFallbackEntry`.',
    );
    exitCode = 66;
    return;
  }

  final env = Platform.environment;

  final port =
      _firstNonEmpty(
        command['port'] as String?,
        env['PORT'],
        env['OSRV_PORT'],
      ) ??
      '3000';

  final hostname =
      _firstNonEmpty(
        command['hostname'] as String?,
        env['HOSTNAME'],
        env['OSRV_HOSTNAME'],
      ) ??
      '0.0.0.0';

  final protocol =
      _firstNonEmpty(command['protocol'] as String?, env['OSRV_PROTOCOL']) ??
      'http';

  final spawnedEnv = <String, String>{
    ...env,
    'PORT': port,
    'HOSTNAME': hostname,
    'OSRV_PORT': port,
    'OSRV_HOSTNAME': hostname,
    'OSRV_PROTOCOL': protocol,
  };

  if (!(command['silent'] as bool)) {
    stdout.writeln(
      '[osrv] serving `$entry` with PORT=$port HOSTNAME=$hostname PROTOCOL=$protocol',
    );
  }

  final child = await Process.start(
    'dart',
    <String>['run', entry],
    mode: ProcessStartMode.inheritStdio,
    environment: spawnedEnv,
  );

  final signalSubscriptions = <StreamSubscription<ProcessSignal>>[];

  void watchSignal(ProcessSignal signal) {
    try {
      signalSubscriptions.add(
        signal.watch().listen((_) {
          if (!child.kill(signal)) {
            child.kill();
          }
        }),
      );
    } on UnsupportedError {
      // Some signals are not supported on all platforms.
    }
  }

  watchSignal(ProcessSignal.sigint);
  watchSignal(ProcessSignal.sigterm);
  if (!Platform.isWindows) {
    watchSignal(ProcessSignal.sighup);
  }

  final childExitCode = await child.exitCode;
  for (final subscription in signalSubscriptions) {
    await subscription.cancel();
  }
  exitCode = childExitCode;
}

Future<void> _runBuild(ArgResults command) async {
  final requestedEntry = command['entry'] as String;
  final outDir = command['out-dir'] as String;
  final silent = command['silent'] as bool;

  try {
    await build(
      BuildOptions(
        entry: requestedEntry,
        outDir: outDir,
        silent: silent,
        defaultEntry: _defaultEntry,
        fallbackEntry: _defaultFallbackEntry,
      ),
      logger: silent ? null : stdout.writeln,
    );
  } on ArgumentError {
    stderr.writeln(
      '[osrv] entry not found. looked for `$requestedEntry` '
      'and fallback `$_defaultFallbackEntry`.',
    );
    exitCode = 66;
    return;
  }
}

String? _firstNonEmpty(String? first, String? second, [String? third]) {
  for (final value in <String?>[first, second, third]) {
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  return null;
}
