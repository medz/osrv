@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'cloudflare fetch export bundle does not include vercel helper imports',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'osrv_fetch_export_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final outputPath = '${tempDir.path}/cloudflare.js';
      final compile = await Process.run('dart', [
        'compile',
        'js',
        'example/cloudflare.dart',
        '-o',
        outputPath,
      ], workingDirectory: _workspacePath);

      expect(
        compile.exitCode,
        0,
        reason: '${compile.stdout}\n${compile.stderr}',
      );

      final output = await File(outputPath).readAsString();
      expect(output, isNot(contains('@vercel/functions')));
      expect(output, isNot(contains('createVercelFetchEntry')));
      expect(output, isNot(contains('loadVercelFunctionHelpers')));
    },
  );
}

final _workspacePath = Directory.current.path;
