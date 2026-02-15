import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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
  _ensureDir('$outDir/shared');
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

  await _writeRuntimeWrappers(
    outDir,
    coreJsName: coreJsName,
  );

  if (!silent) {
    stdout.writeln('[osrv] build complete');
    stdout.writeln('[osrv] js core: $coreJsPath');
    stdout.writeln('[osrv] exe: $exePath');
  }
}

Future<void> _writeRuntimeWrappers(
  String outDir, {
  required String coreJsName,
}) async {
  final templatesRoot = await _resolveTemplatesRoot();
  final vars = <String, String>{'CORE_JS_NAME': coreJsName};

  _writeRenderedTemplate(
    templatesRoot: templatesRoot,
    templatePath: 'shared/bridge.mjs',
    outputPath: '$outDir/shared/bridge.mjs',
  );

  _writeRenderedTemplate(
    templatesRoot: templatesRoot,
    templatePath: 'runtime/node_index.mjs',
    outputPath: '$outDir/js/node/index.mjs',
    vars: vars,
  );
  _writeRenderedTemplate(
    templatesRoot: templatesRoot,
    templatePath: 'runtime/bun_index.mjs',
    outputPath: '$outDir/js/bun/index.mjs',
    vars: vars,
  );
  _writeRenderedTemplate(
    templatesRoot: templatesRoot,
    templatePath: 'runtime/deno_index.mjs',
    outputPath: '$outDir/js/deno/index.mjs',
    vars: vars,
  );

  _writeRenderedTemplate(
    templatesRoot: templatesRoot,
    templatePath: 'edge/cloudflare_index.mjs',
    outputPath: '$outDir/edge/cloudflare/index.mjs',
    vars: vars,
  );
  _writeRenderedTemplate(
    templatesRoot: templatesRoot,
    templatePath: 'edge/vercel_index.mjs',
    outputPath: '$outDir/edge/vercel/index.mjs',
    vars: vars,
  );
  _writeRenderedTemplate(
    templatesRoot: templatesRoot,
    templatePath: 'edge/netlify_index.mjs',
    outputPath: '$outDir/edge/netlify/index.mjs',
    vars: vars,
  );
}

Future<String> _resolveTemplatesRoot() async {
  final packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:osrv/osrv.dart'),
  );

  final packageRoot = packageUri != null
      ? File.fromUri(packageUri).parent.parent.path
      : File.fromUri(Platform.script).parent.parent.path;

  final templatesRoot = '$packageRoot/tool/templates';
  if (!Directory(templatesRoot).existsSync()) {
    throw StateError(
      'osrv template directory not found: $templatesRoot',
    );
  }

  return templatesRoot;
}

void _writeRenderedTemplate({
  required String templatesRoot,
  required String templatePath,
  required String outputPath,
  Map<String, String> vars = const <String, String>{},
}) {
  final template = _readTemplate(templatesRoot, templatePath);
  final rendered = _renderTemplate(template, vars);
  File(outputPath).writeAsStringSync(rendered);
}

String _readTemplate(String templatesRoot, String templatePath) {
  final file = File('$templatesRoot/$templatePath');
  if (!file.existsSync()) {
    throw StateError('Template not found: ${file.path}');
  }

  return file.readAsStringSync();
}

String _renderTemplate(String template, Map<String, String> vars) {
  var rendered = template;
  vars.forEach((key, value) {
    rendered = rendered.replaceAll('{{$key}}', value);
  });

  return rendered;
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

  final configMap = await _evaluateConfigMap(file);
  if (configMap == null) {
    return const _ConfigFile();
  }

  String? readString(String key) {
    final value = configMap[key];
    if (value == null) {
      return null;
    }
    return value.toString();
  }

  return _ConfigFile(
    port: readString('port'),
    hostname: readString('hostname'),
    protocol: readString('protocol'),
  );
}

Future<Map<String, Object?>?> _evaluateConfigMap(File file) async {
  final tempDir = await Directory.systemTemp.createTemp('osrv-config-');
  final runner = File('${tempDir.path}/runner.dart');
  try {
    final configUri = file.absolute.uri.toString();
    runner.writeAsStringSync('''
import 'dart:convert';
import 'dart:io';

import '$configUri';

void main() {
  final dynamic value = osrvConfig;
  if (value is! Map) {
    stderr.writeln('`osrvConfig` must be a Map.');
    exit(2);
  }

  stdout.write(jsonEncode(Map<String, Object?>.from(value)));
}
''');

    final result = await Process.run('dart', <String>[
      'run',
      runner.path,
    ], workingDirectory: file.parent.path);

    if (result.exitCode != 0) {
      stderr.writeln('[osrv] failed to execute config `${file.path}`.');
      if (result.stderr != null && result.stderr.toString().trim().isNotEmpty) {
        stderr.writeln(result.stderr.toString().trim());
      }
      return null;
    }

    final text = result.stdout?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      return null;
    }

    return Map<String, Object?>.from(decoded);
  } finally {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
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
