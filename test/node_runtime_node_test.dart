@TestOn('node')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/node.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

@JS('fetch')
external JSPromise<web.Response> _fetch(JSAny input, [web.RequestInit init]);

void main() {
  test('node runtime serves requests over node:http', () async {
    final runtime = await serve(
      Server(
        fetch: (request, context) => Response.text(
          'hello from ${context.runtime.name}',
          headers: Headers()..set('x-runtime', context.runtime.name),
        ),
      ),
      host: '127.0.0.1',
      port: 0,
    );

    addTearDown(runtime.close);

    expect(runtime.info.name, 'node');
    expect(runtime.info.kind, 'server');
    expect(runtime.url, isNotNull);

    final response = await _fetchText(runtime.url!.resolve('/hello'));
    expect(response.status, 200);
    expect(response.text, 'hello from node');
    expect(response.header('x-runtime'), 'node');
  });

  test(
    'node runtime bridges method, headers, and body into ht.Request',
    () async {
      final runtime = await serve(
        Server(
          fetch: (request, context) async {
            final extension = context.extension<NodeRuntimeExtension>();
            return Response.json({
              'method': request.method,
              'path': request.url.path,
              'query': request.url.queryParameters['mode'],
              'header': request.headers.get('x-test'),
              'body': await request.text(),
              'hasNodeRequest': extension?.request != null,
            });
          },
        ),
        host: '127.0.0.1',
        port: 0,
      );

      addTearDown(runtime.close);

      final response = await _fetchText(
        runtime.url!.resolve('/echo?mode=full'),
        method: 'POST',
        body: 'payload',
        headers: {'x-test': 'yes'},
      );

      expect(response.status, 200);
      expect(jsonDecode(response.text), {
        'method': 'POST',
        'path': '/echo',
        'query': 'full',
        'header': 'yes',
        'body': 'payload',
        'hasNodeRequest': true,
      });
    },
  );

  test(
    'node runtime onError can translate failures into a custom response',
    () async {
      final runtime = await serve(
        Server(
          fetch: (request, context) => throw StateError('boom'),
          onError: (error, stackTrace, context) {
            return Response.text(
              'handled ${context.runtime.name}',
              status: 418,
            );
          },
        ),
        host: '127.0.0.1',
        port: 0,
      );

      addTearDown(runtime.close);

      final response = await _fetchText(runtime.url!.resolve('/fails'));
      expect(response.status, 418);
      expect(response.text, 'handled node');
    },
  );

  test('node runtime streams response bodies over node:http', () async {
    final runtime = await serve(
      Server(
        fetch: (request, context) {
          return Response(
            body: Stream<List<int>>.fromIterable([
              utf8.encode('hello '),
              utf8.encode('stream'),
            ]),
            headers: Headers()..set('x-stream', 'yes'),
          );
        },
      ),
      host: '127.0.0.1',
      port: 0,
    );

    addTearDown(runtime.close);

    expect(runtime.capabilities.streaming, isTrue);

    final response = await _fetchText(runtime.url!.resolve('/stream'));
    expect(response.status, 200);
    expect(response.text, 'hello stream');
    expect(response.header('x-stream'), 'yes');
  });

  test(
    'node runtime does not route transport write failures into onError',
    () async {
      var onErrorCalls = 0;

      final runtime = await serve(
        Server(
          fetch: (request, context) {
            final controller = StreamController<List<int>>();
            controller.add(utf8.encode('hello '));
            scheduleMicrotask(() {
              controller.addError(StateError('stream failed'));
            });
            scheduleMicrotask(() async {
              await controller.close();
            });
            return Response(body: controller.stream);
          },
          onError: (error, stackTrace, context) {
            onErrorCalls++;
            return Response.text('handled node', status: 418);
          },
        ),
        host: '127.0.0.1',
        port: 0,
      );

      addTearDown(runtime.close);

      final response = await _fetchText(runtime.url!.resolve('/broken'));
      expect(response.status, 200);
      expect(response.text, 'hello ');
      expect(onErrorCalls, 0);
    },
  );

  test('node runtime wraps startup hook failures', () async {
    await expectLater(
      () => serve(
        Server(
          onStart: (context) => throw StateError('boom'),
          fetch: (request, context) => Response.text('ok'),
        ),
        host: '127.0.0.1',
        port: 0,
      ),
      throwsA(
        isA<RuntimeStartupError>().having(
          (error) => error.message,
          'message',
          contains('Failed to start node runtime'),
        ),
      ),
    );
  });

  test(
    'node runtime does not dispatch requests before onStart completes',
    () async {
      final startupEntered = Completer<void>();
      final releaseStartup = Completer<void>();
      var fetchCalls = 0;
      final port = 20000 + Random().nextInt(20000);

      final runtimeFuture = serve(
        Server(
          onStart: (context) async {
            startupEntered.complete();
            await releaseStartup.future;
          },
          fetch: (request, context) {
            fetchCalls++;
            return Response.text('started');
          },
        ),
        host: '127.0.0.1',
        port: port,
      );

      await startupEntered.future;

      final responseFuture = _fetchText(
        Uri.parse('http://127.0.0.1:$port/early'),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fetchCalls, 0);

      releaseStartup.complete();

      final runtime = await runtimeFuture;
      addTearDown(runtime.close);

      final response = await responseFuture;
      expect(response.status, 200);
      expect(response.text, 'started');
      expect(fetchCalls, 1);
    },
  );

  test('node runtime.close waits for waitUntil tasks and onStop', () async {
    final waitUntilCompleter = Completer<void>();
    final stopCompleter = Completer<void>();
    var stopCalled = false;

    final runtime = await serve(
      Server(
        fetch: (request, context) {
          context.waitUntil(waitUntilCompleter.future);
          return Response.text('ok');
        },
        onStop: (context) async {
          stopCalled = true;
          await stopCompleter.future;
        },
      ),
      host: '127.0.0.1',
      port: 0,
    );

    await _fetchText(runtime.url!.resolve('/close'));

    var closed = false;
    final closeFuture = runtime.close().then((_) {
      closed = true;
    });

    await Future<void>.delayed(Duration.zero);
    expect(stopCalled, isTrue);
    expect(closed, isFalse);

    stopCompleter.complete();
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);

    waitUntilCompleter.complete();
    await closeFuture;
    expect(closed, isTrue);
  });

  test('node runtime.closed and close surface onStop errors', () async {
    final runtime = await serve(
      Server(
        fetch: (request, context) => Response.text('ok'),
        onStop: (context) => throw StateError('stop failed'),
      ),
      host: '127.0.0.1',
      port: 0,
    );

    final closedExpectation = expectLater(
      runtime.closed,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('stop failed'),
        ),
      ),
    );

    final closeExpectation = expectLater(
      runtime.close(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('stop failed'),
        ),
      ),
    );

    await Future.wait([closedExpectation, closeExpectation]);
  });

  test('node runtime.close waits for in-flight requests to finish', () async {
    final responseCompleter = Completer<void>();
    final requestStarted = Completer<void>();

    final runtime = await serve(
      Server(
        fetch: (request, context) async {
          if (!requestStarted.isCompleted) {
            requestStarted.complete();
          }
          await responseCompleter.future;
          return Response.text('late');
        },
      ),
      host: '127.0.0.1',
      port: 0,
    );

    final responseFuture = _fetchText(runtime.url!.resolve('/slow'));
    await requestStarted.future;

    var closeCompleted = false;
    final closeFuture = runtime.close().then((_) {
      closeCompleted = true;
    });

    await Future<void>.delayed(Duration.zero);
    expect(closeCompleted, isFalse);

    responseCompleter.complete();

    final response = await responseFuture;
    expect(response.status, 200);
    expect(response.text, 'late');

    await closeFuture;
    expect(closeCompleted, isTrue);
  });
}

Future<_FetchResult> _fetchText(
  Uri uri, {
  String method = 'GET',
  String? body,
  Map<String, String>? headers,
}) async {
  final init = headers == null
      ? web.RequestInit(method: method, body: body?.toJS)
      : web.RequestInit(
          method: method,
          body: body?.toJS,
          headers: headers.jsify()! as web.HeadersInit,
        );
  final response = await _fetch(uri.toString().toJS, init).toDart;
  return _FetchResult(
    status: response.status,
    text: (await response.text().toDart).toDart,
    headers: response.headers,
  );
}

final class _FetchResult {
  const _FetchResult({
    required this.status,
    required this.text,
    required this.headers,
  });

  final int status;
  final String text;
  final web.Headers headers;

  String? header(String name) => headers.get(name);
}
