import 'dart:io';

import 'package:args/args.dart';
import 'package:osrv/build.dart';

/// Maintainer convenience wrapper.
///
/// This script is intentionally internal to the osrv repo and calls the same
/// public build API that downstream users can import from `package:osrv/build.dart`.
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
  try {
    await build(
      BuildOptions(
        entry: entry,
        outDir: outDir,
        silent: silent,
        defaultEntry: 'example/server.dart',
        fallbackEntry: 'example/server.dart',
      ),
      logger: silent
          ? null
          : (message) => stdout.writeln('[tool/build] $message'),
    );
  } on ArgumentError catch (error) {
    stderr.writeln('[tool/build] ${error.message}');
    exitCode = 66;
    return;
  }
}
