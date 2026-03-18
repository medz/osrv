@TestOn('node')
library;

import 'package:osrv/osrv.dart' show RuntimeConfigurationError;
import 'package:osrv/runtime/deno.dart';
import 'package:osrv/src/runtime/deno/preflight.dart';
import 'package:osrv/src/runtime/deno/probe.dart';
import 'package:test/test.dart';

void main() {
  test(
    'deno preflight stores a trimmed host value and honest capabilities',
    () {
      final preflight = preflightDenoRuntime(
        host: ' 127.0.0.1 ',
        port: 3000,
        probe: const DenoHostProbe(
          isJavaScriptHost: true,
          hasDenoGlobal: true,
          hasServe: true,
          version: '2.2.0',
          extension: DenoRuntimeExtension(),
        ),
      );

      expect(preflight.host, '127.0.0.1');
      expect(preflight.canServe, isTrue);
      expect(preflight.capabilities.streaming, isTrue);
      expect(preflight.capabilities.websocket, isFalse);
      expect(preflight.capabilities.fileSystem, isTrue);
      expect(preflight.capabilities.backgroundTask, isTrue);
      expect(preflight.capabilities.rawTcp, isTrue);
      expect(preflight.capabilities.nodeCompat, isTrue);
    },
  );

  test('deno preflight blocks when the Deno global is unavailable', () {
    final preflight = preflightDenoRuntime(host: '127.0.0.1', port: 3000);

    expect(preflight.canServe, isFalse);
    expect(preflight.blockReason, isNotNull);
    expect(preflight.blockReason, contains('Deno global object'));
  });

  test('deno preflight blocks when Deno.serve is unavailable', () {
    final preflight = preflightDenoRuntime(
      host: '127.0.0.1',
      port: 3000,
      probe: const DenoHostProbe(
        isJavaScriptHost: true,
        hasDenoGlobal: true,
        hasServe: false,
        version: '2.2.0',
        extension: DenoRuntimeExtension(),
      ),
    );

    expect(preflight.canServe, isFalse);
    expect(preflight.blockReason, isNotNull);
    expect(preflight.blockReason, contains('Deno.serve'));
  });

  test('deno preflight rejects invalid runtime config', () {
    expect(
      () => preflightDenoRuntime(host: '', port: 3000),
      throwsA(isA<RuntimeConfigurationError>()),
    );
    expect(
      () => preflightDenoRuntime(host: '127.0.0.1', port: -1),
      throwsA(isA<RuntimeConfigurationError>()),
    );
    expect(
      () => preflightDenoRuntime(host: '127.0.0.1', port: 65536),
      throwsA(isA<RuntimeConfigurationError>()),
    );
  });
}
