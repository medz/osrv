@TestOn('node')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/cloudflare.dart';
import 'package:osrv/src/runtime/_internal/js/web_stream_bridge.dart';
import 'package:osrv/src/runtime/cloudflare/host.dart'
    show CloudflareWebSocketHost;
import 'package:osrv/src/runtime/cloudflare/server_web_socket.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

@JSExport()
final class _TestExecutionContext {
  int waitUntilCalls = 0;
  final List<Future<JSAny?>> tasks = <Future<JSAny?>>[];

  void waitUntil(JSPromise<JSAny?> task) {
    waitUntilCalls++;
    tasks.add(task.toDart);
  }
}

@JSExport()
final class _FakeCloudflareSocket {
  final Map<String, JSFunction> _listeners = <String, JSFunction>{};
  Object? lastSent;
  int? closeCode;
  String? closeReason;

  void addEventListener(String type, JSFunction listener) {
    _listeners[type] = listener;
  }

  void send(JSAny? data) {
    lastSent = data?.dartify();
  }

  void close([JSAny? code, JSAny? reason]) {
    final dartCode = (code as JSNumber?)?.toDartInt;
    final dartReason = (reason as JSString?)?.toDart;
    if (dartCode == 1004 ||
        dartCode == 1005 ||
        dartCode == 1006 ||
        dartCode == 1015) {
      throw StateError('invalid close code');
    }
    if (dartReason != null && utf8.encode(dartReason).length > 123) {
      throw StateError('close reason too long');
    }

    closeCode = dartCode;
    closeReason = dartReason;
  }
}

const _defaultFetchExportName = '__osrv_fetch__';

void main() {
  tearDown(() {
    globalContext.delete(_defaultFetchExportName.toJS);
    globalContext.delete('__custom_osrv_fetch__'.toJS);
  });

  test('defineFetchExport validates the export name', () {
    expect(
      () => defineFetchExport(
        Server(fetch: (request, context) => Response('ok')),
        name: ' ',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('defineFetchExport bridges fetch into Server.fetch', () async {
    defineFetchExport(
      Server(
        fetch: (request, context) {
          final cf = context
              .extension<CloudflareRuntimeExtension<JSObject, web.Request>>();
          final name = cf?.env?.getProperty<JSString?>('name'.toJS)?.toDart;
          final uri = Uri.parse(request.url);
          final requestPath = cf?.request?.url ?? request.url;

          return Response.json({
            'runtime': context.runtime.name,
            'path': uri.path,
            'request': requestPath,
            'name': name,
            'streaming': context.capabilities.streaming,
            'backgroundTask': context.capabilities.backgroundTask,
            'nodeCompat': context.capabilities.nodeCompat,
            'websocket': context.capabilities.websocket,
          });
        },
      ),
    );

    final env = JSObject()..setProperty('name'.toJS, 'worker'.toJS);
    final ctx = createJSInteropWrapper(_TestExecutionContext());
    final response = await _callWorkerFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/hello'.toJS),
      env,
      ctx,
    );

    expect(response.status, 200);
    expect(jsonDecode((await response.text().toDart).toDart), {
      'runtime': 'cloudflare',
      'path': '/hello',
      'request': 'https://example.com/hello',
      'name': 'worker',
      'streaming': true,
      'backgroundTask': true,
      'nodeCompat': true,
      'websocket': true,
    });
  });

  test('defineFetchExport forwards waitUntil to execution context', () async {
    final waitUntilCompleter = Completer<void>();
    final ctxExport = _TestExecutionContext();
    defineFetchExport(
      Server(
        fetch: (request, context) {
          context.waitUntil(waitUntilCompleter.future);
          return Response('ok');
        },
      ),
    );

    final response = await _callWorkerFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/wait'.toJS),
      JSObject(),
      createJSInteropWrapper(ctxExport),
    );

    expect(response.status, 200);
    expect(ctxExport.waitUntilCalls, 1);

    waitUntilCompleter.complete();
    await Future.wait(ctxExport.tasks);
  });

  test('defineFetchExport exposes request-scoped websocket metadata', () async {
    defineFetchExport(
      Server(
        fetch: (request, context) {
          final webSocket = context.webSocket;
          return Response.json({
            'hasWebSocket': webSocket != null,
            'upgrade': webSocket?.isUpgradeRequest ?? false,
            'protocols': webSocket?.requestedProtocols ?? const <String>[],
          });
        },
      ),
    );

    final upgradeHeaders = web.Headers();
    upgradeHeaders.set('upgrade', 'websocket');
    upgradeHeaders.set('connection', 'Upgrade');
    upgradeHeaders.set('sec-websocket-protocol', 'chat, superchat');

    final upgradeResponse = await _callWorkerFetch(
      _currentFetchHandler(),
      web.Request(
        'https://example.com/chat'.toJS,
        web.RequestInit(headers: upgradeHeaders),
      ),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );
    expect(upgradeResponse.status, 200);
    expect(jsonDecode((await upgradeResponse.text().toDart).toDart), {
      'hasWebSocket': true,
      'upgrade': true,
      'protocols': ['chat', 'superchat'],
    });

    final plainResponse = await _callWorkerFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/plain'.toJS),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );
    expect(plainResponse.status, 200);
    expect(jsonDecode((await plainResponse.text().toDart).toDart), {
      'hasWebSocket': true,
      'upgrade': false,
      'protocols': <String>[],
    });

    final postUpgradeResponse = await _callWorkerFetch(
      _currentFetchHandler(),
      web.Request(
        'https://example.com/chat'.toJS,
        web.RequestInit(method: 'POST', headers: upgradeHeaders),
      ),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );
    expect(postUpgradeResponse.status, 200);
    expect(jsonDecode((await postUpgradeResponse.text().toDart).toDart), {
      'hasWebSocket': true,
      'upgrade': false,
      'protocols': ['chat', 'superchat'],
    });
  });

  test('defineFetchExport uses onError to translate fetch failures', () async {
    CloudflareRuntimeExtension<JSObject, web.Request>? errorExtension;
    RequestContext? errorRequestContext;
    defineFetchExport(
      Server(
        fetch: (request, context) => throw StateError('boom'),
        onError: (error, stackTrace, context) {
          errorExtension = context
              .extension<CloudflareRuntimeExtension<JSObject, web.Request>>();
          if (context is RequestContext) {
            errorRequestContext = context;
          }
          return Response(
            'handled ${context.runtime.name}',
            ResponseInit(status: 418),
          );
        },
      ),
    );

    final response = await _callWorkerFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/error'.toJS),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );

    expect(response.status, 418);
    expect((await response.text().toDart).toDart, 'handled cloudflare');
    expect(errorExtension, isNotNull);
    expect(errorExtension!.request, isNotNull);
    expect(errorRequestContext, isNotNull);
    expect(errorRequestContext!.webSocket, isNotNull);
    expect(errorRequestContext!.webSocket!.isUpgradeRequest, isFalse);
  });

  test('defineFetchExport falls back to 500 when onError throws', () async {
    defineFetchExport(
      Server(
        fetch: (request, context) => throw StateError('boom'),
        onError: (error, stackTrace, context) {
          throw StateError('error in onError');
        },
      ),
    );

    final response = await _callWorkerFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/error-on-error'.toJS),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );

    expect(response.status, 500);
    expect((await response.text().toDart).toDart, 'Internal Server Error');
  });

  test('defineFetchExport rejects raw 101 responses from onError', () async {
    defineFetchExport(
      Server(
        fetch: (request, context) => throw StateError('boom'),
        onError: (error, stackTrace, context) {
          return Response(null, const ResponseInit(status: 101));
        },
      ),
    );

    final response = await _callWorkerFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/raw-101-error'.toJS),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );

    expect(response.status, 500);
    expect((await response.text().toDart).toDart, 'Internal Server Error');
  });

  test('defineFetchExport runs onStart only once', () async {
    var starts = 0;
    defineFetchExport(
      Server(
        onStart: (context) {
          starts++;
        },
        fetch: (request, context) => Response('ok'),
      ),
    );

    final first = await _callWorkerFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/one'.toJS),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );
    final second = await _callWorkerFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/two'.toJS),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );

    expect(first.status, 200);
    expect(second.status, 200);
    expect(starts, 1);
  });

  test('defineFetchExport returns default 500 without onError', () async {
    defineFetchExport(
      Server(fetch: (request, context) => throw StateError('boom')),
    );

    final response = await _callWorkerFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/unhandled'.toJS),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );

    expect(response.status, 500);
    expect((await response.text().toDart).toDart, 'Internal Server Error');
  });

  test(
    'defineFetchExport rejects raw 101 responses outside websocket accept',
    () async {
      defineFetchExport(
        Server(
          fetch: (request, context) {
            return Response(null, const ResponseInit(status: 101));
          },
        ),
      );

      final response = await _callWorkerFetch(
        _currentFetchHandler(),
        web.Request('https://example.com/raw-101'.toJS),
        JSObject(),
        createJSInteropWrapper(_TestExecutionContext()),
      );

      expect(response.status, 500);
      expect((await response.text().toDart).toDart, 'Internal Server Error');
    },
  );

  test('defineFetchExport preserves Response.error semantics', () async {
    defineFetchExport(Server(fetch: (request, context) => Response.error()));

    final response = await _callWorkerFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/error-response'.toJS),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );

    expect(response.type, 'error');
    expect(response.status, 0);
    expect(response.ok, isFalse);
  });

  test('defineFetchExport respects a custom export name', () async {
    defineFetchExport(
      Server(
        fetch: (request, context) => Response(Uri.parse(request.url).path),
      ),
      name: '__custom_osrv_fetch__',
    );

    final response = await _callWorkerFetch(
      _fetchHandlerFor('__custom_osrv_fetch__'),
      web.Request('https://example.com/custom'.toJS),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );

    expect(response.status, 200);
    expect((await response.text().toDart).toDart, '/custom');
  });

  test('defineFetchExport does not pre-read the request stream', () async {
    final entered = Completer<void>();
    final body = StreamController<List<int>>();

    defineFetchExport(
      Server(
        fetch: (request, context) {
          entered.complete();
          return Response(request.method.value);
        },
      ),
    );

    final responseFuture = _callWorkerFetch(
      _currentFetchHandler(),
      web.Request(
        'https://example.com/stream-request'.toJS,
        web.RequestInit(
          method: 'POST',
          body: webReadableStreamFromDartByteStream(body.stream),
          duplex: 'half',
        ),
      ),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );

    await entered.future.timeout(const Duration(milliseconds: 250));

    body.add(utf8.encode('chunk'));
    await body.close();

    final response = await responseFuture;
    expect(response.status, 200);
    expect((await response.text().toDart).toDart, 'POST');
  });

  test('defineFetchExport returns a streaming response immediately', () async {
    final body = StreamController<List<int>>();

    defineFetchExport(
      Server(
        fetch: (request, context) {
          return Response(
            body.stream,
            ResponseInit(headers: Headers()..set('content-type', 'text/plain')),
          );
        },
      ),
    );

    final responseFuture = _callWorkerFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/stream-response'.toJS),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );

    final response = await responseFuture.timeout(
      const Duration(milliseconds: 250),
    );

    expect(response.status, 200);
    expect(response.body, isNotNull);

    body.add(Uint8List.fromList(utf8.encode('Hello ')));
    body.add(Uint8List.fromList(utf8.encode('Osrv!')));
    await body.close();

    expect((await response.text().toDart).toDart, 'Hello Osrv!');
  });

  test(
    'cloudflare websocket adapter keeps the socket open when host close validation fails',
    () async {
      final fakeSocket = _FakeCloudflareSocket();
      final adapter = CloudflareServerWebSocketAdapter(
        createJSInteropWrapper(fakeSocket) as CloudflareWebSocketHost,
        protocol: 'chat',
      );

      await expectLater(adapter.close(1005), throwsStateError);

      adapter.sendText('still-open');
      expect(fakeSocket.lastSent, 'still-open');
    },
  );
}

Future<web.Response> _callWorkerFetch(
  JSFunction fetch,
  web.Request request,
  JSObject env,
  JSObject ctx,
) {
  return fetch.callMethodVarArgs<JSPromise<web.Response>>('call'.toJS, [
    null,
    request,
    env,
    ctx,
  ]).toDart;
}

JSFunction _currentFetchHandler() {
  return _fetchHandlerFor(_defaultFetchExportName);
}

JSFunction _fetchHandlerFor(String name) {
  return globalContext.getProperty<JSFunction?>(name.toJS)!;
}
