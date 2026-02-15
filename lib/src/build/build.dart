import 'dart:io';
import 'dart:isolate';

typedef BuildLogger = void Function(String message);

final class BuildOptions {
  const BuildOptions({
    this.entry = 'server.dart',
    this.outDir = 'dist',
    this.silent = false,
    this.dartExecutable = 'dart',
    this.workingDirectory,
    this.defaultEntry = 'server.dart',
    this.fallbackEntry = 'bin/server.dart',
  });

  final String entry;
  final String outDir;
  final bool silent;
  final String dartExecutable;
  final String? workingDirectory;
  final String defaultEntry;
  final String fallbackEntry;
}

final class BuildResult {
  const BuildResult({
    required this.entry,
    required this.outDir,
    required this.coreJsPath,
    required this.executablePath,
  });

  final String entry;
  final String outDir;
  final String coreJsPath;
  final String executablePath;
}

String? resolveEntry(
  String preferred, {
  String defaultEntry = 'server.dart',
  String fallbackEntry = 'bin/server.dart',
  String? workingDirectory,
}) {
  if (_fileExists(preferred, workingDirectory: workingDirectory)) {
    return preferred;
  }

  if (preferred == defaultEntry &&
      _fileExists(fallbackEntry, workingDirectory: workingDirectory)) {
    return fallbackEntry;
  }

  return null;
}

Future<BuildResult> build(BuildOptions options, {BuildLogger? logger}) async {
  final resolvedEntry = resolveEntry(
    options.entry,
    defaultEntry: options.defaultEntry,
    fallbackEntry: options.fallbackEntry,
    workingDirectory: options.workingDirectory,
  );
  if (resolvedEntry == null) {
    throw ArgumentError(
      'Entry not found. Tried `${options.entry}` '
      'and fallback `${options.fallbackEntry}`.',
    );
  }

  _ensureDir(
    '${options.outDir}/js/core',
    workingDirectory: options.workingDirectory,
  );
  _ensureDir(
    '${options.outDir}/js/node',
    workingDirectory: options.workingDirectory,
  );
  _ensureDir(
    '${options.outDir}/js/bun',
    workingDirectory: options.workingDirectory,
  );
  _ensureDir(
    '${options.outDir}/js/deno',
    workingDirectory: options.workingDirectory,
  );
  _ensureDir(
    '${options.outDir}/edge/cloudflare',
    workingDirectory: options.workingDirectory,
  );
  _ensureDir(
    '${options.outDir}/edge/vercel',
    workingDirectory: options.workingDirectory,
  );
  _ensureDir(
    '${options.outDir}/edge/netlify',
    workingDirectory: options.workingDirectory,
  );
  _ensureDir(
    '${options.outDir}/shared',
    workingDirectory: options.workingDirectory,
  );
  _ensureDir(
    '${options.outDir}/bin',
    workingDirectory: options.workingDirectory,
  );

  final baseName = _basenameWithoutExtension(resolvedEntry);
  final coreJsName = '$baseName.js';
  final coreJsPath = '${options.outDir}/js/core/$coreJsName';
  final exeName = Platform.isWindows ? '$baseName.exe' : baseName;
  final exePath = '${options.outDir}/bin/$exeName';

  await _run(
    options.dartExecutable,
    <String>['compile', 'js', resolvedEntry, '-o', coreJsPath],
    silent: options.silent,
    logger: logger,
    workingDirectory: options.workingDirectory,
  );

  await _run(
    options.dartExecutable,
    <String>['compile', 'exe', resolvedEntry, '-o', exePath],
    silent: options.silent,
    logger: logger,
    workingDirectory: options.workingDirectory,
  );

  await _writeRuntimeWrappers(
    options.outDir,
    coreJsName: coreJsName,
    workingDirectory: options.workingDirectory,
  );

  if (!options.silent && logger != null) {
    logger('[osrv] build complete');
    logger('[osrv] js core: $coreJsPath');
    logger('[osrv] exe: $exePath');
  }

  return BuildResult(
    entry: resolvedEntry,
    outDir: options.outDir,
    coreJsPath: coreJsPath,
    executablePath: exePath,
  );
}

Future<void> _writeRuntimeWrappers(
  String outDir, {
  required String coreJsName,
  String? workingDirectory,
}) async {
  final templatesRoot = await _resolveTemplatesRoot();
  final vars = <String, String>{'CORE_JS_NAME': coreJsName};

  _writeRenderedTemplate(
    templatesRoot: templatesRoot,
    templatePath: 'shared/bridge.mjs',
    outputPath: '$outDir/shared/bridge.mjs',
    workingDirectory: workingDirectory,
  );

  _writeRenderedTemplate(
    templatesRoot: templatesRoot,
    templatePath: 'runtime/node.mjs',
    outputPath: '$outDir/js/node/index.mjs',
    vars: vars,
    workingDirectory: workingDirectory,
  );
  _writeRenderedTemplate(
    templatesRoot: templatesRoot,
    templatePath: 'runtime/bun.mjs',
    outputPath: '$outDir/js/bun/index.mjs',
    vars: vars,
    workingDirectory: workingDirectory,
  );
  _writeRenderedTemplate(
    templatesRoot: templatesRoot,
    templatePath: 'runtime/deno.mjs',
    outputPath: '$outDir/js/deno/index.mjs',
    vars: vars,
    workingDirectory: workingDirectory,
  );

  _writeRenderedTemplate(
    templatesRoot: templatesRoot,
    templatePath: 'edge/cloudflare.mjs',
    outputPath: '$outDir/edge/cloudflare/index.mjs',
    vars: vars,
    workingDirectory: workingDirectory,
  );
  _writeRenderedTemplate(
    templatesRoot: templatesRoot,
    templatePath: 'edge/vercel.mjs',
    outputPath: '$outDir/edge/vercel/index.mjs',
    vars: vars,
    workingDirectory: workingDirectory,
  );
  _writeRenderedTemplate(
    templatesRoot: templatesRoot,
    templatePath: 'edge/netlify.mjs',
    outputPath: '$outDir/edge/netlify/index.mjs',
    vars: vars,
    workingDirectory: workingDirectory,
  );
}

Future<String> _resolveTemplatesRoot() async {
  final packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:osrv/build.dart'),
  );

  final packageRoot = packageUri != null
      ? File.fromUri(packageUri).parent.parent.path
      : File.fromUri(Platform.script).parent.parent.path;

  final templatesRoot = '$packageRoot/lib/src/build/templates';
  if (!Directory(templatesRoot).existsSync()) {
    throw StateError('osrv template directory not found: $templatesRoot');
  }

  return templatesRoot;
}

void _writeRenderedTemplate({
  required String templatesRoot,
  required String templatePath,
  required String outputPath,
  required String? workingDirectory,
  Map<String, String> vars = const <String, String>{},
}) {
  final template = _readTemplate(templatesRoot, templatePath);
  final rendered = _renderTemplate(template, vars);
  _resolveFile(
    outputPath,
    workingDirectory: workingDirectory,
  ).writeAsStringSync(rendered);
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
  required BuildLogger? logger,
  required String? workingDirectory,
}) async {
  if (!silent && logger != null) {
    logger('\$ $executable ${arguments.join(' ')}');
  }

  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
    workingDirectory: workingDirectory,
  );

  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(executable, arguments, 'Command failed', code);
  }
}

void _ensureDir(String path, {required String? workingDirectory}) {
  final dir = _resolveDirectory(path, workingDirectory: workingDirectory);
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

bool _fileExists(String path, {required String? workingDirectory}) {
  return _resolveFile(path, workingDirectory: workingDirectory).existsSync();
}

File _resolveFile(String path, {required String? workingDirectory}) {
  if (workingDirectory == null || _isAbsolutePath(path)) {
    return File(path);
  }

  return File('$workingDirectory${Platform.pathSeparator}$path');
}

Directory _resolveDirectory(String path, {required String? workingDirectory}) {
  if (workingDirectory == null || _isAbsolutePath(path)) {
    return Directory(path);
  }

  return Directory('$workingDirectory${Platform.pathSeparator}$path');
}

bool _isAbsolutePath(String path) {
  if (path.startsWith('/') || path.startsWith(r'\\')) {
    return true;
  }

  return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path);
}
