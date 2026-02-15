import 'dart:io';

import 'package:args/args.dart';

const String _defaultEntry = 'server.dart';

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
    ..addOption(
      'config',
      defaultsTo: 'osrv.config.dart',
      help: 'Config file path.',
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
  final entry = _resolveEntry(command['entry'] as String);
  if (entry == null) {
    stderr.writeln(
      '[osrv] entry not found. looked for `${command['entry']}` '
      'and fallback `bin/server.dart`.',
    );
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
      '[osrv] serving `$entry` with PORT=$port HOSTNAME=$hostname PROTOCOL=$protocol',
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
  final entry = _resolveEntry(command['entry'] as String);
  if (entry == null) {
    stderr.writeln(
      '[osrv] entry not found. looked for `${command['entry']}` '
      'and fallback `bin/server.dart`.',
    );
    exitCode = 66;
    return;
  }

  final outDir = command['out-dir'] as String;
  final silent = command['silent'] as bool;
  final baseName = _basenameWithoutExtension(entry);

  _ensureDir('$outDir/js/core');
  _ensureDir('$outDir/js/node');
  _ensureDir('$outDir/js/bun');
  _ensureDir('$outDir/js/deno');
  _ensureDir('$outDir/edge/cloudflare');
  _ensureDir('$outDir/edge/vercel');
  _ensureDir('$outDir/edge/netlify');
  _ensureDir('$outDir/bin');

  final coreJsName = '$baseName.js';
  final coreJsPath = '$outDir/js/core/$coreJsName';
  final exeName = Platform.isWindows ? '$baseName.exe' : baseName;
  final exePath = '$outDir/bin/$exeName';

  await _run('dart', <String>[
    'compile',
    'js',
    entry,
    '-o',
    coreJsPath,
  ], silent: silent);

  await _run('dart', <String>[
    'compile',
    'exe',
    entry,
    '-o',
    exePath,
  ], silent: silent);

  _writeRuntimeWrappers(outDir, coreJsName);

  if (!silent) {
    stdout.writeln('[osrv] build complete');
    stdout.writeln('[osrv] js core: $coreJsPath');
    stdout.writeln('[osrv] exe: $exePath');
  }
}

void _writeRuntimeWrappers(String outDir, String coreJsName) {
  File('$outDir/js/node/index.mjs').writeAsStringSync('''
import '../core/$coreJsName';

export function serve(options = {}) {
  throw new Error(
    'osrv node adapter scaffold generated. Bridge runtime requests to globalThis.__osrv_main__.',
  );
}
''');

  File('$outDir/js/bun/index.mjs').writeAsStringSync('''
import '../core/$coreJsName';

export function serve(options = {}) {
  throw new Error(
    'osrv bun adapter scaffold generated. Bridge runtime requests to globalThis.__osrv_main__.',
  );
}
''');

  File('$outDir/js/deno/index.mjs').writeAsStringSync('''
import '../core/$coreJsName';

export function serve(options = {}) {
  throw new Error(
    'osrv deno adapter scaffold generated. Bridge runtime requests to globalThis.__osrv_main__.',
  );
}
''');

  File('$outDir/edge/cloudflare/index.mjs').writeAsStringSync('''
import '../../js/core/$coreJsName';

export default {
  async fetch(request, env, ctx) {
    if (typeof globalThis.__osrv_main__ === 'function') {
      return globalThis.__osrv_main__(request, { env, ctx, provider: 'cloudflare' });
    }

    return new Response('osrv Cloudflare adapter scaffold generated.', { status: 501 });
  },
};
''');

  File('$outDir/edge/vercel/index.mjs').writeAsStringSync('''
import '../../js/core/$coreJsName';

export default async function handler(request, context) {
  if (typeof globalThis.__osrv_main__ === 'function') {
    return globalThis.__osrv_main__(request, {
      env: context?.env ?? {},
      ctx: context,
      provider: 'vercel',
    });
  }

  return new Response('osrv Vercel adapter scaffold generated.', { status: 501 });
}
''');

  File('$outDir/edge/netlify/index.mjs').writeAsStringSync('''
import '../../js/core/$coreJsName';

export default async (request, context) => {
  if (typeof globalThis.__osrv_main__ === 'function') {
    return globalThis.__osrv_main__(request, {
      env: context?.env ?? {},
      ctx: context,
      provider: 'netlify',
    });
  }

  return new Response('osrv Netlify adapter scaffold generated.', { status: 501 });
};
''');
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  required bool silent,
}) async {
  if (!silent) {
    stdout.writeln('\$ $executable ${arguments.join(' ')}');
  }

  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
  );

  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(executable, arguments, 'Command failed', code);
  }
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

String? _resolveEntry(String preferred) {
  final preferredFile = File(preferred);
  if (preferredFile.existsSync()) {
    return preferred;
  }

  if (preferred == _defaultEntry) {
    final fallback = File('bin/server.dart');
    if (fallback.existsSync()) {
      return 'bin/server.dart';
    }
  }

  return null;
}

void _ensureDir(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
}

String _basenameWithoutExtension(String path) {
  final normalized = path.replaceAll('\\', '/');
  final fileName = normalized.split('/').last;
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex <= 0) {
    return fileName;
  }

  return fileName.substring(0, dotIndex);
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
