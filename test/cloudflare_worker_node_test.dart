@TestOn('node')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:osrv/esm.dart';
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/cloudflare.dart';
import 'package:osrv/src/runtime/_internal/js/web_stream_bridge.dart';
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

void main() {
  tearDown(() {
    globalContext.delete(defaultFetchEntryName.toJS);
    globalContext.delete('__custom_osrv_fetch__'.toJS);
  });

  test('defineFetchEntry validates the export name', () {
    expect(
      () => defineFetchEntry(
        Server(
          fetch: (request, context) => Response.text('ok'),
        ),
        runtime: const CloudflareFetchRuntime(),
        name: ' ',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('defineFetchEntry bridges fetch into Server.fetch', () async {
    defineFetchEntry(
      Server(
        fetch: (request, context) {
          final cf = context.extension<
              CloudflareRuntimeExtension<JSObject, web.Request>>();
          final name = cf?.env?.getProperty<JSString?>('name'.toJS)?.toDart;
          final requestPath = cf?.request?.url ?? request.url.toString();

          return Response.json({
            'runtime': context.runtime.name,
            'path': request.url.path,
            'request': requestPath,
            'name': name,
            'streaming': context.capabilities.streaming,
            'backgroundTask': context.capabilities.backgroundTask,
            'nodeCompat': context.capabilities.nodeCompat,
            'websocket': context.capabilities.websocket,
          });
        },
      ),
      runtime: const CloudflareFetchRuntime(),
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
    expect(
      jsonDecode((await response.text().toDart).toDart),
      {
        'runtime': 'cloudflare',
        'path': '/hello',
        'request': 'https://example.com/hello',
        'name': 'worker',
        'streaming': true,
        'backgroundTask': true,
        'nodeCompat': true,
        'websocket': false,
      },
    );
  });

  test('defineFetchEntry forwards waitUntil to execution context', () async {
    final waitUntilCompleter = Completer<void>();
    final ctxExport = _TestExecutionContext();
    defineFetchEntry(
      Server(
        fetch: (request, context) {
          context.waitUntil(waitUntilCompleter.future);
          return Response.text('ok');
        },
      ),
      runtime: const CloudflareFetchRuntime(),
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

  test('defineFetchEntry uses onError to translate fetch failures', () async {
    defineFetchEntry(
      Server(
        fetch: (request, context) => throw StateError('boom'),
        onError: (error, stackTrace, context) {
          return Response.text(
            'handled ${context.runtime.name}',
            status: 418,
          );
        },
      ),
      runtime: const CloudflareFetchRuntime(),
    );

    final response = await _callWorkerFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/error'.toJS),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );

    expect(response.status, 418);
    expect((await response.text().toDart).toDart, 'handled cloudflare');
  });

  test('defineFetchEntry runs onStart only once', () async {
    var starts = 0;
    defineFetchEntry(
      Server(
        onStart: (context) {
          starts++;
        },
        fetch: (request, context) => Response.text('ok'),
      ),
      runtime: const CloudflareFetchRuntime(),
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

  test('defineFetchEntry returns default 500 without onError', () async {
    defineFetchEntry(
      Server(
        fetch: (request, context) => throw StateError('boom'),
      ),
      runtime: const CloudflareFetchRuntime(),
    );

    final response = await _callWorkerFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/unhandled'.toJS),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );

    expect(response.status, 500);
    expect(
      (await response.text().toDart).toDart,
      'Internal Server Error',
    );
  });

  test('defineFetchEntry respects a custom export name', () async {
    defineFetchEntry(
      Server(
        fetch: (request, context) => Response.text(request.url.path),
      ),
      runtime: const CloudflareFetchRuntime(),
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

  test('defineFetchEntry does not pre-read the request stream', () async {
    final entered = Completer<void>();
    final body = StreamController<List<int>>();

    defineFetchEntry(
      Server(
        fetch: (request, context) {
          entered.complete();
          return Response.text(request.method);
        },
      ),
      runtime: const CloudflareFetchRuntime(),
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

  test('defineFetchEntry returns a streaming response immediately', () async {
    final body = StreamController<List<int>>();

    defineFetchEntry(
      Server(
        fetch: (request, context) {
          return Response(
            body: body.stream,
            headers: Headers()..set('content-type', 'text/plain'),
          );
        },
      ),
      runtime: const CloudflareFetchRuntime(),
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
}

Future<web.Response> _callWorkerFetch(
  JSFunction fetch,
  web.Request request,
  JSObject env,
  JSObject ctx,
) {
  return fetch
      .callMethodVarArgs<JSPromise<web.Response>>(
        'call'.toJS,
        [null, request, env, ctx],
      )
      .toDart;
}

JSFunction _currentFetchHandler() {
  return _fetchHandlerFor(defaultFetchEntryName);
}

JSFunction _fetchHandlerFor(String name) {
  return globalContext.getProperty<JSFunction?>(name.toJS)!;
}
