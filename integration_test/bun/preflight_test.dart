@TestOn('node')
library;

import 'package:osrv/runtime/bun.dart';
import 'package:osrv/src/runtime/bun/preflight.dart';
import 'package:osrv/src/runtime/bun/probe.dart';
import 'package:test/test.dart';

void main() {
  test('bun preflight stores a trimmed host value', () {
    final preflight = preflightBunRuntime(
      host: ' 127.0.0.1 ',
      port: 3000,
      probe: const BunHostProbe(
        isJavaScriptHost: true,
        hasBunGlobal: true,
        hasServe: true,
        version: '1.0.0',
        extension: BunRuntimeExtension(),
      ),
    );

    expect(preflight.host, '127.0.0.1');
    expect(preflight.canServe, isTrue);
  });
}
