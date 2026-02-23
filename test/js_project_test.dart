import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'js runtime integration project (bun)',
    () async {
      final hasBun = await _hasCommand('bun');
      if (!hasBun) {
        return;
      }

      final jsDir = Directory('test/js').path;

      final install = await Process.run('bun', <String>[
        'install',
      ], workingDirectory: jsDir);
      expect(
        install.exitCode,
        0,
        reason: 'bun install failed\n${install.stdout}\n${install.stderr}',
      );

      final run = await Process.run('bun', <String>[
        'test',
      ], workingDirectory: jsDir);
      expect(
        run.exitCode,
        0,
        reason: 'bun test failed\n${run.stdout}\n${run.stderr}',
      );
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Future<bool> _hasCommand(String command) async {
  try {
    final result = await Process.run(command, <String>['--version']);
    return result.exitCode == 0;
  } on Object {
    return false;
  }
}
