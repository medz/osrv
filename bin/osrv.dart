import 'dart:io';

import 'package:args/args.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addCommand('serve')
    ..addCommand('build');

  parser.commands['serve']!
    ..addOption('entry', help: 'Dart entry file that boots your fetch handler.')
    ..addOption('port', help: 'Port to listen on.')
    ..addOption('hostname', help: 'Hostname to bind to.')
    ..addOption(
      'protocol',
      allowed: <String>['http', 'https'],
      help: 'Protocol preference.',
    )
    ..addOption(
      'config',
      defaultsTo: 'osrv.config.dart',
      help: 'Config file path.',
    )
    ..addFlag('silent', defaultsTo: false, help: 'Silence osrv CLI logs.');

  parser.commands['build']!.addFlag('silent', defaultsTo: false);

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
  }
}

Future<void> _runServe(ArgResults command) async {
  final entry = command['entry'] as String?;
  if (entry == null || entry.isEmpty) {
    stderr.writeln('[osrv] --entry is required for `osrv serve`.');
    exitCode = 64;
    return;
  }

  final entryFile = File(entry);
  if (!entryFile.existsSync()) {
    stderr.writeln('[osrv] entry file not found: $entry');
    exitCode = 66;
    return;
  }

  final configPath = command['config'] as String;
  final fileConfig = await _loadConfigFile(configPath);
  final env = Platform.environment;

  final port =
      _firstNonEmpty(
        command['port'] as String?,
        env['PORT'],
        env['OSRV_PORT'],
      ) ??
      fileConfig.port ??
      '3000';

  final hostname =
      _firstNonEmpty(
        command['hostname'] as String?,
        env['HOSTNAME'],
        env['OSRV_HOSTNAME'],
      ) ??
      fileConfig.hostname ??
      '0.0.0.0';

  final protocol =
      _firstNonEmpty(command['protocol'] as String?, env['OSRV_PROTOCOL']) ??
      fileConfig.protocol ??
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
      '[osrv] launching `$entry` with PORT=$port HOSTNAME=$hostname PROTOCOL=$protocol',
    );
  }

  final child = await Process.start(
    'dart',
    <String>['run', entry],
    mode: ProcessStartMode.inheritStdio,
    environment: spawnedEnv,
  );

  exitCode = await child.exitCode;
}

Future<void> _runBuild(ArgResults command) async {
  final child = await Process.start(
    'dart',
    <String>['run', 'tool/build.dart'],
    mode: ProcessStartMode.inheritStdio,
    environment: Platform.environment,
  );

  exitCode = await child.exitCode;
}

Future<_ConfigFile> _loadConfigFile(String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    return const _ConfigFile();
  }

  final source = await file.readAsString();
  final portMatch = RegExp(
    r'''['"]?port['"]?\s*:\s*(\d+)''',
  ).firstMatch(source);
  final hostMatch = RegExp(
    r'''['"]?hostname['"]?\s*:\s*['"]([^'"]+)['"]''',
  ).firstMatch(source);
  final protocolMatch = RegExp(
    r'''['"]?protocol['"]?\s*:\s*['"](http|https)['"]''',
  ).firstMatch(source);

  return _ConfigFile(
    port: portMatch?.group(1),
    hostname: hostMatch?.group(1),
    protocol: protocolMatch?.group(1),
  );
}

String? _firstNonEmpty(String? first, String? second, [String? third]) {
  for (final value in <String?>[first, second, third]) {
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  return null;
}

final class _ConfigFile {
  const _ConfigFile({this.port, this.hostname, this.protocol});

  final String? port;
  final String? hostname;
  final String? protocol;
}
