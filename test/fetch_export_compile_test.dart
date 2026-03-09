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

  test('node serve bundle does not include bun runtime code', () async {
    final tempDir = await Directory.systemTemp.createTemp('osrv_node_bundle_');
    addTearDown(() => tempDir.delete(recursive: true));

    final outputPath = '${tempDir.path}/node.js';
    final compile = await Process.run('dart', [
      'compile',
      'js',
      'example/node.dart',
      '-o',
      outputPath,
    ], workingDirectory: _workspacePath);

    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');

    final output = await File(outputPath).readAsString();
    expect(output, isNot(contains('serveBunRuntime')));
    expect(output, isNot(contains('probeBunHost')));
    expect(output, isNot(contains('Bun runtime requires Bun.serve')));
  });

  test('bun serve bundle does not include node runtime code', () async {
    final tempDir = await Directory.systemTemp.createTemp('osrv_bun_bundle_');
    addTearDown(() => tempDir.delete(recursive: true));

    final outputPath = '${tempDir.path}/bun.js';
    final compile = await Process.run('dart', [
      'compile',
      'js',
      'example/bun.dart',
      '-o',
      outputPath,
    ], workingDirectory: _workspacePath);

    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');

    final output = await File(outputPath).readAsString();
    expect(output, isNot(contains('serveNodeRuntime')));
    expect(output, isNot(contains('node:http')));
    expect(
      output,
      isNot(contains('Node runtime requires the node:http host module')),
    );
  });
}

final _workspacePath = Directory.current.path;
