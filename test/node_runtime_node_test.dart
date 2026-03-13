@TestOn('node')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/node.dart';
import 'package:osrv/src/runtime/_internal/js/web_stream_bridge.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

@JS('fetch')
external JSPromise<web.Response> _fetch(JSAny input, [web.RequestInit init]);

@JS('require')
external JSFunction? get _require;

extension type _NodeHttpModule._(JSObject _) implements JSObject {
  @JS('request')
  external JSFunction get request;
}

extension type _NodeClientRequest._(JSObject _) implements JSObject {
  @JS('flushHeaders')
  external JSFunction get flushHeaders;

  external JSFunction get write;
  external JSFunction get end;
  external JSFunction get on;
}

extension type _NodeClientResponse._(JSObject _) implements JSObject {
  external JSAny? get statusCode;
  external JSFunction get on;

  @JS('setEncoding')
  external JSFunction get setEncoding;
}

void main() {
  test('node runtime serves requests over node:http', () async {
    final runtime = await serve(
      Server(
        fetch: (request, context) => Response(
          'hello from ${context.runtime.name}',
          ResponseInit(
            headers: Headers()..set('x-runtime', context.runtime.name),
          ),
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
            final uri = Uri.parse(request.url);
            return Response.json({
              'method': request.method.value,
              'path': uri.path,
              'query': uri.queryParameters['mode'],
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
            return Response(
              'handled ${context.runtime.name}',
              ResponseInit(status: 418),
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
            Stream<List<int>>.fromIterable([
              utf8.encode('hello '),
              utf8.encode('stream'),
            ]),
            ResponseInit(headers: Headers()..set('x-stream', 'yes')),
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

  test('node runtime does not pre-read the request stream', () async {
    final entered = Completer<void>();

    final runtime = await serve(
      Server(
        fetch: (request, context) {
          entered.complete();
          return Response(request.method.value);
        },
      ),
      host: '127.0.0.1',
      port: 0,
    );

    addTearDown(runtime.close);

    final request = _openNodeStreamingRequest(
      runtime.url!.resolve('/stream-request'),
      method: 'POST',
    );
    final responseFuture = request.response;

    request.flushHeaders();

    await entered.future.timeout(const Duration(milliseconds: 250));

    request.write(utf8.encode('chunk'));
    await request.end();

    final response = await responseFuture;
    expect(response.status, 200);
    expect(response.text, 'POST');
  });

  test(
    'node runtime bridges request streams after headers are flushed',
    () async {
      final received = Completer<String>();

      final runtime = await serve(
        Server(
          fetch: (request, context) async {
            received.complete(await request.text());
            return Response('ok');
          },
        ),
        host: '127.0.0.1',
        port: 0,
      );

      addTearDown(runtime.close);

      final request = _openNodeStreamingRequest(
        runtime.url!.resolve('/stream-body'),
        method: 'POST',
      );
      final responseFuture = request.response;

      request.flushHeaders();
      request.write(utf8.encode('chunk'));
      await request.end();

      final response = await responseFuture;
      expect(response.status, 200);
      expect(response.text, 'ok');
      expect(await received.future, 'chunk');
    },
  );

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
            return Response(controller.stream);
          },
          onError: (error, stackTrace, context) {
            onErrorCalls++;
            return Response('handled node', ResponseInit(status: 418));
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
          fetch: (request, context) => Response('ok'),
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
            return Response('started');
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
          return Response('ok');
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
        fetch: (request, context) => Response('ok'),
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
          return Response('late');
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
  return _fetchResponse(uri, init);
}

Future<_FetchResult> _fetchResponse(Uri uri, web.RequestInit init) async {
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

_NodeStreamingRequest _openNodeStreamingRequest(
  Uri uri, {
  String method = 'POST',
}) {
  final module = _NodeHttpModule._(
    _require!.callAsFunction(null, 'node:http'.toJS)! as JSObject,
  );
  final response = Completer<_FetchResult>();
  final path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;

  final request = _NodeClientRequest._(
    module.request.callAsFunction(
          module,
          {
                'method': method,
                'hostname': uri.host,
                'port': uri.port,
                'path': path,
              }.jsify()!
              as JSObject,
          ((JSObject rawResponse) {
            final clientResponse = _NodeClientResponse._(rawResponse);
            final buffer = StringBuffer();

            clientResponse.setEncoding.callAsFunction(
              clientResponse,
              'utf8'.toJS,
            );
            clientResponse.on.callAsFunction(
              clientResponse,
              'data'.toJS,
              ((JSString chunk) {
                buffer.write(chunk.toDart);
              }).toJS,
            );
            clientResponse.on.callAsFunction(
              clientResponse,
              'end'.toJS,
              (() {
                response.complete(
                  _FetchResult(
                    status: (clientResponse.statusCode as JSNumber).toDartInt,
                    text: buffer.toString(),
                    headers: web.Headers(),
                  ),
                );
              }).toJS,
            );
          }).toJS,
        )!
        as JSObject,
  );

  request.on.callAsFunction(
    request,
    'error'.toJS,
    ((JSAny? error) {
      if (response.isCompleted) {
        return;
      }
      response.completeError(
        StateError(error?.dartify().toString() ?? 'request failed'),
      );
    }).toJS,
  );

  return _NodeStreamingRequest(request: request, response: response.future);
}

final class _NodeStreamingRequest {
  const _NodeStreamingRequest({required this.request, required this.response});

  final _NodeClientRequest request;
  final Future<_FetchResult> response;

  void flushHeaders() {
    request.flushHeaders.callAsFunction(request);
  }

  void write(List<int> chunk) {
    request.write.callAsFunction(request, Uint8List.fromList(chunk).toJS);
  }

  Future<void> end() {
    final completer = Completer<void>();
    request.end.callAsFunction(
      request,
      (() {
        completer.complete();
      }).toJS,
    );
    return completer.future;
  }
}
