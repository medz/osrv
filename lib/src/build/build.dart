import 'dart:io';

final class BuildOptions {
  const BuildOptions({
    this.entry = 'server.dart',
    this.outDir = 'dist',
    this.workingDirectory,
    this.defaultEntry = 'server.dart',
    this.fallbackEntry = 'bin/server.dart',
    this.silent = false,
  });

  final String entry;
  final String outDir;
  final String? workingDirectory;
  final String defaultEntry;
  final String fallbackEntry;
  final bool silent;
}

final class BuildResult {
  const BuildResult({
    required this.entry,
    required this.outDir,
    required this.executablePath,
    required this.artifacts,
  });

  final String entry;
  final String outDir;
  final String executablePath;
  final Map<String, String> artifacts;
}

Future<BuildResult> build(
  BuildOptions options, {
  void Function(String message)? logger,
}) async {
  final log = logger ?? (String _) {};
  final cwd = options.workingDirectory ?? Directory.current.path;

  final resolvedEntry = _resolveEntry(cwd, options);
  final outDir = _resolvePath(cwd, options.outDir);
  Directory(outDir).createSync(recursive: true);

  final appJs = _join(outDir, 'app.js');
  await _runCompile(
    cwd: cwd,
    args: <String>['compile', 'js', resolvedEntry, '-O4', '-o', appJs],
    silent: options.silent,
    log: log,
  );

  final executableDir = _join(outDir, 'bin');
  Directory(executableDir).createSync(recursive: true);
  final executablePath = _join(
    executableDir,
    Platform.isWindows ? 'server.exe' : 'server',
  );
  await _runCompile(
    cwd: cwd,
    args: <String>['compile', 'exe', resolvedEntry, '-o', executablePath],
    silent: options.silent,
    log: log,
  );

  final nodeEntry = _join(outDir, 'js/node/index.mjs');
  final bunEntry = _join(outDir, 'js/bun/index.mjs');
  final denoEntry = _join(outDir, 'js/deno/index.mjs');

  _writeFile(nodeEntry, _runtimeAdapter);
  _writeFile(bunEntry, _runtimeAdapter);
  _writeFile(denoEntry, _runtimeAdapter);

  final cloudflareEntry = _join(outDir, 'edge/cloudflare/index.mjs');
  final vercelEntry = _join(outDir, 'edge/vercel/index.mjs');
  final netlifyEntry = _join(outDir, 'edge/netlify/index.mjs');

  _writeFile(cloudflareEntry, _cloudflareAdapter);
  _writeFile(vercelEntry, _edgeExportAdapter);
  _writeFile(netlifyEntry, _edgeExportAdapter);

  if (!options.silent) {
    log('[osrv] built $outDir');
  }

  return BuildResult(
    entry: resolvedEntry,
    outDir: outDir,
    executablePath: executablePath,
    artifacts: <String, String>{
      'app': appJs,
      'bin': executablePath,
      'js.node': nodeEntry,
      'js.bun': bunEntry,
      'js.deno': denoEntry,
      'edge.cloudflare': cloudflareEntry,
      'edge.vercel': vercelEntry,
      'edge.netlify': netlifyEntry,
    },
  );
}

Future<void> _runCompile({
  required String cwd,
  required List<String> args,
  required bool silent,
  required void Function(String message) log,
}) async {
  if (!silent) {
    log('[osrv] dart ${args.join(' ')}');
  }

  final result = await Process.run(
    Platform.resolvedExecutable,
    args,
    workingDirectory: cwd,
  );

  if (result.exitCode != 0) {
    throw ProcessException(
      Platform.resolvedExecutable,
      args,
      [
        result.stdout,
        result.stderr,
      ].where((line) => line != null && '$line'.trim().isNotEmpty).join('\n'),
      result.exitCode,
    );
  }
}

String _resolveEntry(String cwd, BuildOptions options) {
  final preferred = _resolvePath(cwd, options.entry);
  if (File(preferred).existsSync()) {
    return preferred;
  }

  final fallbackCandidates = <String>{
    options.defaultEntry,
    options.fallbackEntry,
  };
  for (final candidate in fallbackCandidates) {
    final resolved = _resolvePath(cwd, candidate);
    if (File(resolved).existsSync()) {
      return resolved;
    }
  }

  throw ArgumentError(
    'Cannot resolve server entry. Tried: ${options.entry}, '
    '${options.defaultEntry}, ${options.fallbackEntry}.',
  );
}

String _resolvePath(String cwd, String path) {
  if (path.startsWith('/')) {
    return path;
  }
  return _join(cwd, path);
}

void _writeFile(String filePath, String content) {
  final file = File(filePath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

String _join(String base, String next) {
  if (base.endsWith('/')) {
    return '$base$next';
  }
  return '$base/$next';
}

const String _runtimeAdapter = '''import '../../app.js';
''';

const String _cloudflareAdapter = '''import '../../app.js';

export default {
  fetch: globalThis.__osrv_fetch__,
};
''';

const String _edgeExportAdapter = '''import '../../app.js';

export const fetch = globalThis.__osrv_fetch__;
''';
