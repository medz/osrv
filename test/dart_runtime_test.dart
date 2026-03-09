@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/dart.dart';
import 'package:test/test.dart';

void main() {
  test('serve starts a dart runtime and handles a request', () async {
    final server = Server(
      fetch: (request, context) async {
        expect(context.runtime.name, 'dart');
        final ext = context.extension<DartRuntimeExtension>();
        expect(ext, isNotNull);
        expect(ext!.request, isNotNull);
        expect(ext.response, isNotNull);
        expect(ext.server.port, greaterThanOrEqualTo(0));
        return Response.text('hello ${request.url.path}');
      },
    );

    final runtime = await serve(server, host: '127.0.0.1', port: 0);

    addTearDown(() async {
      await runtime.close();
      await runtime.closed;
    });

    final client = HttpClient();
    addTearDown(client.close);

    final request = await client.getUrl(runtime.url!.resolve('/ping'));
    final response = await request.close();
    final body = await response.transform(SystemEncoding().decoder).join();

    expect(response.statusCode, HttpStatus.ok);
    expect(body, 'hello /ping');
  });

  test('serve rejects invalid dart runtime config', () async {
    final server = Server(fetch: (request, context) => Response.text('ok'));

    expect(
      () => serve(server, host: '', port: 3000),
      throwsA(isA<RuntimeConfigurationError>()),
    );
  });

  test('serve wraps dart runtime startup hook failures', () async {
    final server = Server(
      onStart: (_) {
        throw StateError('boom');
      },
      fetch: (request, context) => Response.text('ok'),
    );

    await expectLater(
      () => serve(server, host: '127.0.0.1', port: 0),
      throwsA(isA<RuntimeStartupError>()),
    );
  });

  test('onError can translate fetch failures into a custom response', () async {
    final server = Server(
      onError: (error, stackTrace, context) {
        expect(error, isA<StateError>());
        expect(context.runtime.name, 'dart');
        return Response.text('handled', status: 418);
      },
      fetch: (request, context) {
        throw StateError('boom');
      },
    );

    final runtime = await serve(server, host: '127.0.0.1', port: 0);

    addTearDown(() async {
      await runtime.close();
      await runtime.closed;
    });

    final client = HttpClient();
    addTearDown(client.close);

    final request = await client.getUrl(runtime.url!.resolve('/handled'));
    final response = await request.close();
    final body = await response.transform(SystemEncoding().decoder).join();

    expect(response.statusCode, 418);
    expect(body, 'handled');
  });

  test('unhandled fetch failures produce default 500 response', () async {
    final server = Server(
      fetch: (request, context) {
        throw StateError('boom');
      },
    );

    final runtime = await serve(server, host: '127.0.0.1', port: 0);

    addTearDown(() async {
      await runtime.close();
      await runtime.closed;
    });

    final client = HttpClient();
    addTearDown(client.close);

    final request = await client.getUrl(runtime.url!.resolve('/default-500'));
    final response = await request.close();
    final body = await response.transform(SystemEncoding().decoder).join();

    expect(response.statusCode, HttpStatus.internalServerError);
    expect(body, 'Internal Server Error');
  });

  test('request bridge preserves method, query, headers, and body', () async {
    final server = Server(
      fetch: (request, context) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/echo');
        expect(request.url.queryParameters['x'], '1');
        expect(request.headers.get('x-test-header'), 'yes');
        expect(await request.text(), 'payload');
        return Response.json({
          'method': request.method,
          'query': request.url.queryParameters['x'],
          'header': request.headers.get('x-test-header'),
        });
      },
    );

    final runtime = await serve(server, host: '127.0.0.1', port: 0);

    addTearDown(() async {
      await runtime.close();
      await runtime.closed;
    });

    final client = HttpClient();
    addTearDown(client.close);

    final request = await client.postUrl(runtime.url!.resolve('/echo?x=1'));
    request.headers.set('x-test-header', 'yes');
    request.write('payload');

    final response = await request.close();
    final body = await response.transform(SystemEncoding().decoder).join();

    expect(response.statusCode, HttpStatus.ok);
    expect(body, contains('"method":"POST"'));
    expect(body, contains('"query":"1"'));
    expect(body, contains('"header":"yes"'));
  });

  test('response bridge writes streaming bodies and custom headers', () async {
    final server = Server(
      fetch: (request, context) {
        final stream = Stream<List<int>>.fromIterable([
          utf8.encode('hello '),
          utf8.encode('stream'),
        ]);

        return Response(
          body: stream,
          status: HttpStatus.accepted,
          statusText: 'Accepted Custom',
          headers: Headers.fromEntries([const MapEntry('x-stream', 'yes')]),
        );
      },
    );

    final runtime = await serve(server, host: '127.0.0.1', port: 0);

    addTearDown(() async {
      await runtime.close();
      await runtime.closed;
    });

    final client = HttpClient();
    addTearDown(client.close);

    final request = await client.getUrl(runtime.url!.resolve('/stream'));
    final response = await request.close();
    final body = await response.transform(SystemEncoding().decoder).join();

    expect(response.statusCode, HttpStatus.accepted);
    expect(response.reasonPhrase, 'Accepted Custom');
    expect(response.headers.value('x-stream'), 'yes');
    expect(body, 'hello stream');
  });

  test('response bridge writes repeated set-cookie headers', () async {
    final server = Server(
      fetch: (request, context) {
        final headers = Headers()
          ..append('set-cookie', 'a=1; Path=/')
          ..append('set-cookie', 'b=2; Path=/');
        return Response.text('cookies', headers: headers);
      },
    );

    final runtime = await serve(server, host: '127.0.0.1', port: 0);

    addTearDown(() async {
      await runtime.close();
      await runtime.closed;
    });

    final client = HttpClient();
    addTearDown(client.close);

    final request = await client.getUrl(runtime.url!.resolve('/cookies'));
    final response = await request.close();
    await response.drain();

    final cookies = response.headers['set-cookie'];
    expect(cookies, isNotNull);
    expect(cookies, hasLength(2));
    expect(cookies, contains('a=1; Path=/'));
    expect(cookies, contains('b=2; Path=/'));
  });

  test('runtime.close waits for waitUntil tasks and onStop', () async {
    final backgroundTask = Completer<void>();
    final onStop = Completer<void>();

    final server = Server(
      onStop: (_) => onStop.future,
      fetch: (request, context) async {
        context.waitUntil(backgroundTask.future);
        return Response.text('ok');
      },
    );

    final runtime = await serve(server, host: '127.0.0.1', port: 0);

    addTearDown(() async {
      if (!backgroundTask.isCompleted) {
        backgroundTask.complete();
      }
      if (!onStop.isCompleted) {
        onStop.complete();
      }
      await runtime.close();
    });

    final client = HttpClient();
    addTearDown(client.close);

    final request = await client.getUrl(runtime.url!.resolve('/wait'));
    final response = await request.close();
    await response.drain();

    var closed = false;
    unawaited(
      runtime.closed.then(
        (_) {
          closed = true;
        },
        onError: (_) {
          closed = true;
        },
      ),
    );

    final closeFuture = runtime.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(closed, isFalse);

    backgroundTask.complete();
    onStop.complete();

    await closeFuture;
    expect(closed, isTrue);
  });

  test('runtime.closed completes with error when onStop fails', () async {
    final server = Server(
      onStop: (_) {
        throw StateError('stop failed');
      },
      fetch: (request, context) => Response.text('ok'),
    );

    final runtime = await serve(server, host: '127.0.0.1', port: 0);

    final client = HttpClient();
    addTearDown(client.close);

    final request = await client.getUrl(runtime.url!.resolve('/stop-error'));
    final response = await request.close();
    await response.drain();

    final closedExpectation = expectLater(
      runtime.closed,
      throwsA(isA<StateError>()),
    );
    await expectLater(runtime.close, throwsA(isA<StateError>()));
    await closedExpectation;
  });
}
