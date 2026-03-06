@TestOn('vm')
library;

import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/bun.dart';
import 'package:osrv/src/runtime/bun/preflight.dart';
import 'package:osrv/src/runtime/bun/probe.dart';
import 'package:test/test.dart';

void main() {
  test('bun runtime extension has a compile-safe first-cut shape', () {
    const ext = BunRuntimeExtension();
    expect(ext.bun, isNull);
  });

  test('bun runtime extension can be created from the current host', () {
    final ext = BunRuntimeExtension.host();
    expect(ext.bun, isNull);
  });

  test('bun host probe is compile-safe on the current VM host', () {
    final probe = probeBunHost();
    expect(probe.isJavaScriptHost, isFalse);
    expect(probe.hasBunGlobal, isFalse);
    expect(probe.hasServe, isFalse);
    expect(probe.isBunHost, isFalse);
    expect(probe.version, isNull);
    expect(probe.extension.bun, isNull);
  });

  test('bun runtime preflight is compile-safe on the current VM host', () {
    final preflight = preflightBunRuntime(
      const BunRuntimeConfig(host: '127.0.0.1', port: 3000),
    );

    expect(preflight.info.name, 'bun');
    expect(preflight.info.kind, 'javascript-host');
    expect(preflight.capabilities.streaming, isTrue);
    expect(preflight.capabilities.fileSystem, isTrue);
    expect(preflight.capabilities.backgroundTask, isTrue);
    expect(preflight.capabilities.nodeCompat, isTrue);
    expect(preflight.isJavaScriptHost, isFalse);
    expect(preflight.hasBunGlobal, isFalse);
    expect(preflight.hasServe, isFalse);
    expect(preflight.isBunHost, isFalse);
    expect(preflight.bunVersion, 'unknown');
    expect(preflight.summary, 'non-js-host');
    expect(preflight.canServe, isFalse);
    expect(preflight.blockReason, contains('not JavaScript'));
    expect(preflight.extension.bun, isNull);
    expect(preflight.toUnsupportedError().message, contains('not JavaScript'));
  });

  test(
    'bun runtime preflight reports missing Bun.serve on a Bun-like host',
    () {
      final preflight = preflightBunRuntime(
        const BunRuntimeConfig(host: '127.0.0.1', port: 3000),
        probe: const BunHostProbe(
          isJavaScriptHost: true,
          hasBunGlobal: true,
          hasServe: false,
          version: '1.2.0',
          extension: BunRuntimeExtension(),
        ),
      );

      expect(preflight.isJavaScriptHost, isTrue);
      expect(preflight.hasBunGlobal, isTrue);
      expect(preflight.hasServe, isFalse);
      expect(preflight.isBunHost, isTrue);
      expect(preflight.bunVersion, '1.2.0');
      expect(preflight.summary, 'bun-host-without-serve');
      expect(preflight.canServe, isFalse);
      expect(preflight.blockReason, contains('Bun.serve'));
    },
  );

  test('bun runtime preflight reports a serve-ready Bun host', () {
    final preflight = preflightBunRuntime(
      const BunRuntimeConfig(host: '127.0.0.1', port: 3000),
      probe: const BunHostProbe(
        isJavaScriptHost: true,
        hasBunGlobal: true,
        hasServe: true,
        version: '1.2.0',
        extension: BunRuntimeExtension(),
      ),
    );

    expect(preflight.summary, 'bun-host(1.2.0)');
    expect(preflight.canServe, isTrue);
    expect(preflight.blockReason, isNull);
  });

  test('serve rejects invalid bun runtime config', () async {
    final server = Server(fetch: (request, context) => Response.text('ok'));

    await expectLater(
      () => serve(server, const BunRuntimeConfig(host: '', port: 3000)),
      throwsA(isA<RuntimeConfigurationError>()),
    );
  });

  test('serve reports when the current host is not Bun', () async {
    final server = Server(fetch: (request, context) => Response.text('ok'));

    await expectLater(
      () =>
          serve(server, const BunRuntimeConfig(host: '127.0.0.1', port: 3000)),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('not JavaScript'),
        ),
      ),
    );
  });
}
