import 'dart:io';

import 'package:args/args.dart';

/// Maintainer convenience wrapper.
///
/// This script is intentionally internal to the osrv repo and delegates to the
/// user-facing CLI build command so there is only one build implementation path.
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'entry',
      defaultsTo: 'example/server.dart',
      help: 'Dart entry file used for maintainer build smoke output.',
    )
    ..addOption(
      'out-dir',
      defaultsTo: 'dist',
      help: 'Output directory passed through to `dart run osrv build`.',
    )
    ..addFlag(
      'silent',
      defaultsTo: false,
      help: 'Pass --silent to `dart run osrv build`.',
    );

  ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on FormatException catch (error) {
    stderr.writeln('[tool/build] ${error.message}');
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  final entry = parsed['entry'] as String;
  final outDir = parsed['out-dir'] as String;
  final silent = parsed['silent'] as bool;

  final command = <String>[
    'run',
    'osrv',
    'build',
    '--entry',
    entry,
    '--out-dir',
    outDir,
    if (silent) '--silent',
  ];

  stdout.writeln(
    '[tool/build] maintainer helper: delegating to `dart ${command.join(' ')}`',
  );

  final process = await Process.start(
    'dart',
    command,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException('dart', command, 'Command failed', code);
  }
}
