import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/node.dart';
import 'package:osrv/src/runtime/node/http_host.dart';
import 'package:osrv/src/runtime/node/listener.dart';
import 'package:osrv/src/runtime/node/preflight.dart';
import 'package:osrv/src/runtime/node/probe.dart';
import 'package:osrv/src/runtime/node/request_bridge.dart';
import 'package:osrv/src/runtime/node/response_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('node runtime extension has a compile-safe first-cut shape', () {
    const ext = NodeRuntimeExtension();
    expect(ext.process, isNull);
    expect(ext.server, isNull);
    expect(ext.request, isNull);
    expect(ext.response, isNull);
  });

  test('node runtime extension can be created from the current host', () {
    final ext = NodeRuntimeExtension.host();
    expect(ext.process, isNull);
  });

  test('node http host selection is compile-safe on the current VM host', () {
    expect(nodeHttpModule, isNull);
  });

  test(
    'node request listener callback is compile-safe with empty extension',
    () async {
      var invoked = false;
      final callback = createNodeHostRequestCallback((
        request,
        response,
        extension,
      ) {
        invoked = true;
      });

      await expectLater(
        callback(const NodeRuntimeExtension()),
        throwsA(isA<StateError>()),
      );
      expect(invoked, isFalse);
    },
  );

  test('node request bridge extracts request head from stub host', () {
    const request = NodeIncomingMessageHost(
      method: 'GET',
      url: '/hello?x=1',
      headers: {'x-test': 'yes'},
      body: 'ignored-body',
    );

    final snapshot = nodeRequestHeadFromHost(request);
    expect(snapshot.method, 'GET');
    expect(snapshot.url, '/hello?x=1');
    expect(snapshot.rawHeaders, isA<Map<String, Object?>>());
    expect((snapshot.rawHeaders as Map<String, Object?>)['x-test'], 'yes');
    expect(snapshot.rawBody, 'ignored-body');
  });

  test(
    'node request bridge converts request snapshot into ht.Request with string body',
    () async {
      const request = NodeIncomingMessageHost(
        method: 'POST',
        url: '/hello?x=1',
        headers: {
          'x-test': 'yes',
          'set-cookie': ['a=1', 'b=2'],
          'ignored': 123,
        },
        body: 'payload',
      );

      final snapshot = nodeRequestHeadFromHost(request);
      final bridged = nodeRequestFromHeadSnapshot(
        snapshot,
        origin: Uri.parse('http://127.0.0.1:3000'),
      );

      expect(bridged.method, 'POST');
      expect(bridged.url.toString(), 'http://127.0.0.1:3000/hello?x=1');
      expect(bridged.headers.get('x-test'), 'yes');
      expect(bridged.headers.getAll('set-cookie'), ['a=1', 'b=2']);
      expect(bridged.headers.has('ignored'), isFalse);
      expect(await bridged.text(), 'payload');
    },
  );

  test(
    'node request bridge converts request snapshot into ht.Request with bytes body',
    () async {
      const request = NodeIncomingMessageHost(
        method: 'POST',
        url: '/bytes',
        body: [104, 105],
      );

      final snapshot = nodeRequestHeadFromHost(request);
      final bridged = nodeRequestFromHeadSnapshot(
        snapshot,
        origin: Uri.parse('http://127.0.0.1:3000'),
      );

      expect(await bridged.text(), 'hi');
    },
  );

  test(
    'node request bridge drops unsupported materialized body values',
    () async {
      const request = NodeIncomingMessageHost(
        method: 'POST',
        url: '/unsupported',
        body: 123,
      );

      final snapshot = nodeRequestHeadFromHost(request);
      final bridged = nodeRequestFromHeadSnapshot(
        snapshot,
        origin: Uri.parse('http://127.0.0.1:3000'),
      );

      expect(await bridged.text(), '');
    },
  );

  test('node request bridge preserves stream bodies from stub host', () async {
    final request = NodeIncomingMessageHost(
      method: 'POST',
      url: '/stream',
      body: Stream<List<int>>.fromIterable([
        [104, 101],
        [108, 108, 111],
      ]),
    );

    final bridged = await nodeRequestFromHost(
      request,
      origin: Uri.parse('http://127.0.0.1:3000'),
    );

    expect(bridged.method, 'POST');
    expect(bridged.url.toString(), 'http://127.0.0.1:3000/stream');
    expect(await bridged.text(), 'hello');
  });

  test('node request bridge surfaces stub body stream failures', () async {
    const request = NodeIncomingMessageHost(
      method: 'POST',
      url: '/broken',
      bodyError: 'request failed',
    );

    await expectLater(
      nodeRequestFromHost(request, origin: Uri.parse('http://127.0.0.1:3000')),
      throwsA(
        isA<Object>().having(
          (error) => error.toString(),
          'message',
          contains('request failed'),
        ),
      ),
    );
  });

  test(
    'node response bridge writes status, headers, and body to stub host',
    () async {
      final response = Response.text(
        'hello',
        status: 201,
        statusText: 'Created',
        headers: Headers()
          ..set('x-runtime', 'node')
          ..append('set-cookie', 'a=1')
          ..append('set-cookie', 'b=2'),
      );
      final target = NodeServerResponseHost();

      await writeHtResponseToNodeServerResponse(response, target);

      expect(target.statusCode, 201);
      expect(target.statusMessage, 'Created');
      expect(target.headers['x-runtime'], 'node');
      expect(target.headers['set-cookie'], ['a=1', 'b=2']);
      expect(target.ended, isTrue);
      expect(target.chunks, hasLength(1));
      expect(String.fromCharCodes(target.chunks.single), 'hello');
    },
  );

  test('node response bridge streams chunks to stub host', () async {
    final response = Response(
      body: Stream<List<int>>.fromIterable([
        [104, 101],
        [108, 108, 111],
      ]),
      status: 200,
    );
    final target = NodeServerResponseHost();

    await writeHtResponseToNodeServerResponse(response, target);

    expect(target.ended, isTrue);
    expect(target.chunks, hasLength(2));
    expect(String.fromCharCodes(target.chunks[0]), 'he');
    expect(String.fromCharCodes(target.chunks[1]), 'llo');
  });

  test('node response bridge surfaces stub write failures', () async {
    final response = Response(
      body: Stream<List<int>>.fromIterable([
        [104, 105],
      ]),
    );
    final target = NodeServerResponseHost(writeError: 'write failed');

    await expectLater(
      () => writeHtResponseToNodeServerResponse(response, target),
      throwsA(
        isA<NodeTransportWriteError>().having(
          (error) => error.cause.toString(),
          'cause',
          contains('write failed'),
        ),
      ),
    );
  });

  test('node response bridge surfaces stub end failures', () async {
    final response = Response.text('ok');
    final target = NodeServerResponseHost(endError: 'end failed');

    await expectLater(
      () => writeHtResponseToNodeServerResponse(response, target),
      throwsA(
        isA<NodeTransportWriteError>().having(
          (error) => error.cause.toString(),
          'cause',
          contains('end failed'),
        ),
      ),
    );
  });

  test('node host probe is compile-safe on the current VM host', () {
    final probe = probeNodeHost();
    expect(probe.isJavaScriptHost, isFalse);
    expect(probe.hasNodeProcess, isFalse);
    expect(probe.isNodeHost, isFalse);
    expect(probe.nodeVersion, isNull);
    expect(probe.extension.process, isNull);
  });

  test('node runtime preflight is compile-safe on the current VM host', () {
    final preflight = preflightNodeRuntime(
      const NodeRuntimeConfig(host: '127.0.0.1', port: 3000),
    );

    expect(preflight.info.name, 'node');
    expect(preflight.info.kind, 'javascript-host');
    expect(preflight.capabilities.nodeCompat, isTrue);
    expect(preflight.capabilities.streaming, isTrue);
    expect(preflight.isJavaScriptHost, isFalse);
    expect(preflight.hasNodeProcess, isFalse);
    expect(preflight.isNodeHost, isFalse);
    expect(preflight.hasHttpModule, isFalse);
    expect(preflight.nodeVersion, 'unknown');
    expect(preflight.summary, 'non-js-host');
    expect(preflight.canServe, isFalse);
    expect(preflight.blockReason, contains('not JavaScript'));
    expect(preflight.extension.process, isNull);
    expect(preflight.toUnsupportedError().message, contains('not JavaScript'));
  });

  test(
    'node runtime preflight reports missing node:http module on a Node-like host',
    () {
      final preflight = preflightNodeRuntime(
        const NodeRuntimeConfig(host: '127.0.0.1', port: 3000),
        probe: const NodeHostProbe(
          isJavaScriptHost: true,
          hasNodeProcess: true,
          nodeVersion: 'v22.0.0',
          extension: NodeRuntimeExtension(),
        ),
        httpModule: null,
      );

      expect(preflight.isJavaScriptHost, isTrue);
      expect(preflight.hasNodeProcess, isTrue);
      expect(preflight.isNodeHost, isTrue);
      expect(preflight.hasHttpModule, isFalse);
      expect(preflight.nodeVersion, 'v22.0.0');
      expect(preflight.summary, 'node-host-without-http-module');
      expect(preflight.canServe, isFalse);
      expect(preflight.blockReason, contains('node:http'));
    },
  );

  test('serve rejects invalid node runtime config', () async {
    final server = Server(fetch: (request, context) => Response.text('ok'));

    await expectLater(
      () => serve(server, const NodeRuntimeConfig(host: '', port: 3000)),
      throwsA(isA<RuntimeConfigurationError>()),
    );
  });

  test('serve reports when the current host is not Node.js', () async {
    final server = Server(fetch: (request, context) => Response.text('ok'));

    await expectLater(
      () =>
          serve(server, const NodeRuntimeConfig(host: '127.0.0.1', port: 3000)),
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
