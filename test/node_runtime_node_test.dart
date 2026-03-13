@TestOn('node')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/node.dart';
import 'package:osrv/src/runtime/node/http_host.dart'
    show NodeIncomingMessageHost;
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
  external JSAny? get rawHeaders;
  external JSFunction get on;

  @JS('setEncoding')
  external JSFunction get setEncoding;
}

extension type _NodeIncomingMessageReadableState._(JSObject _)
    implements JSObject {
  external JSAny? get readableFlowing;
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

  test('node runtime preserves repeated set-cookie headers', () async {
    final runtime = await serve(
      Server(
        fetch: (request, context) {
          final headers = Headers()
            ..append('set-cookie', 'a=1; Path=/')
            ..append('set-cookie', 'b=2; Path=/');
          return Response('cookies', ResponseInit(headers: headers));
        },
      ),
      host: '127.0.0.1',
      port: 0,
    );

    addTearDown(runtime.close);

    final request = _openNodeStreamingRequest(
      runtime.url!.resolve('/cookies'),
      method: 'GET',
    );
    final responseFuture = request.response;
    await request.end();
    final response = await responseFuture;

    expect(response.status, 200);
    expect(response.rawHeaderValues('set-cookie'), [
      'a=1; Path=/',
      'b=2; Path=/',
    ]);
  });

  for (final method in _nonPreReadRequestMethods) {
    test('node runtime does not pre-read the $method request stream', () async {
      await _expectNodeRuntimeDoesNotPreReadRequestStream(method);
    });
  }

  test(
    'node runtime bridges POST request streams after headers are flushed',
    () async {
      await _expectNodeRuntimeBridgesRequestStreamAfterHeadersAreFlushed(
        'POST',
      );
    },
  );

  test(
    'node runtime keeps the host request paused until body consumption starts',
    () async {
      final entered = Completer<bool?>();
      final releaseBodyRead = Completer<void>();
      final received = Completer<String>();

      final runtime = await serve(
        Server(
          fetch: (request, context) async {
            final extension = context.extension<NodeRuntimeExtension>();
            if (!entered.isCompleted) {
              entered.complete(_nodeReadableFlowing(extension!.request!));
            }

            await releaseBodyRead.future;

            final body = await request.text();
            if (!received.isCompleted) {
              received.complete(body);
            }

            return Response('ok');
          },
        ),
        host: '127.0.0.1',
        port: 0,
      );

      addTearDown(runtime.close);

      final request = _openNodeStreamingRequest(
        runtime.url!.resolve('/paused-body'),
        method: 'POST',
      );
      final responseFuture = request.response;

      request.flushHeaders();

      expect(await entered.future, isNot(true));

      request.write(utf8.encode('chunk'));
      await request.end();
      releaseBodyRead.complete();

      final response = await responseFuture;
      expect(response.status, 200);
      expect(response.text, 'ok');
      expect(await received.future, 'chunk');
    },
  );

  test(
    'node runtime maps body subscription pause and resume to the host request',
    () async {
      final firstChunk = Completer<void>();
      final resumeBody = Completer<void>();
      final pausedFlowing = Completer<bool?>();
      final resumedFlowing = Completer<bool?>();

      final runtime = await serve(
        Server(
          fetch: (request, context) async {
            final extension = context.extension<NodeRuntimeExtension>()!;
            final rawRequest = extension.request!;
            final chunks = <String>[];
            final done = Completer<void>();
            late final StreamSubscription<Uint8List> subscription;

            subscription = request.body!.listen(
              (chunk) {
                chunks.add(utf8.decode(chunk));
                if (chunks.length != 1) {
                  return;
                }

                subscription.pause();
                if (!pausedFlowing.isCompleted) {
                  scheduleMicrotask(() {
                    if (!pausedFlowing.isCompleted) {
                      pausedFlowing.complete(_nodeReadableFlowing(rawRequest));
                    }
                  });
                }
                if (!firstChunk.isCompleted) {
                  firstChunk.complete();
                }

                unawaited(
                  resumeBody.future.then((_) {
                    subscription.resume();
                    if (!resumedFlowing.isCompleted) {
                      scheduleMicrotask(() {
                        if (!resumedFlowing.isCompleted) {
                          resumedFlowing.complete(
                            _nodeReadableFlowing(rawRequest),
                          );
                        }
                      });
                    }
                  }),
                );
              },
              onDone: () {
                if (!done.isCompleted) {
                  done.complete();
                }
              },
              onError: done.completeError,
            );

            await done.future;

            return Response.json({
              'body': chunks.join(),
              'pausedFlowing': await pausedFlowing.future,
              'resumedFlowing': await resumedFlowing.future,
            });
          },
        ),
        host: '127.0.0.1',
        port: 0,
      );

      addTearDown(runtime.close);

      final request = _openNodeStreamingRequest(
        runtime.url!.resolve('/paused-resumed-body'),
        method: 'POST',
      );
      final responseFuture = request.response;

      request.flushHeaders();
      request.write(utf8.encode('first-'));

      await firstChunk.future;

      request.write(utf8.encode('second'));
      resumeBody.complete();
      await request.end();

      final response = await responseFuture;
      expect(response.status, 200);
      expect(jsonDecode(response.text), {
        'body': 'first-second',
        'pausedFlowing': false,
        'resumedFlowing': true,
      });
    },
  );

  test(
    'node runtime drains discarded request bodies after body subscription cancel',
    () async {
      final canceledFlowing = Completer<bool?>();
      final canceled = Completer<void>();

      final runtime = await serve(
        Server(
          fetch: (request, context) async {
            final extension = context.extension<NodeRuntimeExtension>()!;
            final rawRequest = extension.request!;
            late final StreamSubscription<Uint8List> subscription;

            subscription = request.body!.listen((chunk) {
              if (canceled.isCompleted) {
                return;
              }

              unawaited(
                subscription.cancel().then((_) {
                  scheduleMicrotask(() {
                    if (!canceledFlowing.isCompleted) {
                      canceledFlowing.complete(
                        _nodeReadableFlowing(rawRequest),
                      );
                    }
                    if (!canceled.isCompleted) {
                      canceled.complete();
                    }
                  });
                }),
              );
            });

            await canceled.future;

            return Response.json({
              'canceledFlowing': await canceledFlowing.future,
            });
          },
        ),
        host: '127.0.0.1',
        port: 0,
      );

      addTearDown(runtime.close);

      final request = _openNodeStreamingRequest(
        runtime.url!.resolve('/discarded-body'),
        method: 'POST',
      );
      final responseFuture = request.response;

      request.flushHeaders();
      request.write(utf8.encode('first-'));

      await canceled.future;

      request.write(utf8.encode('second'));
      await request.end();

      final response = await responseFuture;
      expect(response.status, 200);
      expect(jsonDecode(response.text), {'canceledFlowing': true});
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
    final stopEntered = Completer<void>();
    var stopCalled = false;

    final runtime = await serve(
      Server(
        fetch: (request, context) {
          context.waitUntil(waitUntilCompleter.future);
          return Response('ok');
        },
        onStop: (context) async {
          stopCalled = true;
          if (!stopEntered.isCompleted) {
            stopEntered.complete();
          }
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

    await stopEntered.future;
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

const _nonPreReadRequestMethods = ['POST', 'GET', 'HEAD'];

Future<void> _expectNodeRuntimeDoesNotPreReadRequestStream(
  String method,
) async {
  final entered = Completer<void>();
  final releaseResponse = Completer<void>();

  final runtime = await serve(
    Server(
      fetch: (request, context) async {
        if (!entered.isCompleted) {
          entered.complete();
        }
        await releaseResponse.future;
        return Response(
          null,
          ResponseInit(
            headers: Headers()..set('x-method', request.method.value),
          ),
        );
      },
    ),
    host: '127.0.0.1',
    port: 0,
  );

  addTearDown(runtime.close);

  final request = _openNodeStreamingRequest(
    runtime.url!.resolve('/stream-request'),
    method: method,
  );
  final responseFuture = request.response;

  request.flushHeaders();

  await entered.future;
  await request.end();
  releaseResponse.complete();

  final response = await responseFuture;
  expect(response.status, 200);
  expect(response.text, isEmpty);
  expect(response.rawHeaderValues('x-method'), [method]);
}

Future<void> _expectNodeRuntimeBridgesRequestStreamAfterHeadersAreFlushed(
  String method,
) async {
  final received = Completer<String>();

  final runtime = await serve(
    Server(
      fetch: (request, context) async {
        final body = await request.text();
        if (!received.isCompleted) {
          received.complete(body);
        }
        return Response(
          null,
          ResponseInit(
            headers: Headers()..set('x-method', request.method.value),
          ),
        );
      },
    ),
    host: '127.0.0.1',
    port: 0,
  );

  addTearDown(runtime.close);

  final request = _openNodeStreamingRequest(
    runtime.url!.resolve('/stream-body'),
    method: method,
  );
  final responseFuture = request.response;

  request.flushHeaders();
  request.write(utf8.encode('chunk'));
  await request.end();

  final response = await responseFuture;
  expect(response.status, 200);
  expect(response.text, isEmpty);
  expect(response.rawHeaderValues('x-method'), [method]);
  expect(await received.future, 'chunk');
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
    this.rawHeaders = const <String>[],
  });

  final int status;
  final String text;
  final web.Headers headers;
  final List<String> rawHeaders;

  String? header(String name) => headers.get(name);

  List<String> rawHeaderValues(String name) {
    final values = <String>[];
    for (var index = 0; index + 1 < rawHeaders.length; index += 2) {
      if (rawHeaders[index].toLowerCase() == name.toLowerCase()) {
        values.add(rawHeaders[index + 1]);
      }
    }
    return values;
  }
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
              'error'.toJS,
              ((JSAny? error) {
                if (response.isCompleted) {
                  return;
                }
                response.completeError(
                  StateError(error?.dartify().toString() ?? 'response failed'),
                );
              }).toJS,
            );
            clientResponse.on.callAsFunction(
              clientResponse,
              'end'.toJS,
              (() {
                if (response.isCompleted) {
                  return;
                }
                response.complete(
                  _FetchResult(
                    status: (clientResponse.statusCode as JSNumber).toDartInt,
                    text: buffer.toString(),
                    headers: web.Headers(),
                    rawHeaders: _rawHeadersFromNodeResponse(clientResponse),
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

List<String> _rawHeadersFromNodeResponse(_NodeClientResponse response) {
  final rawHeaders = response.rawHeaders?.dartify();
  if (rawHeaders is! List) {
    return const <String>[];
  }

  return rawHeaders.whereType<String>().toList(growable: false);
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

bool? _nodeReadableFlowing(NodeIncomingMessageHost request) {
  final value = _NodeIncomingMessageReadableState._(
    request as JSObject,
  ).readableFlowing;
  return value?.dartify() as bool?;
}
