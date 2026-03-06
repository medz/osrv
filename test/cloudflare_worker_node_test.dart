@TestOn('node')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/cloudflare.dart';
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
    globalContext.delete(defaultCloudflareFetchName.toJS);
    globalContext.delete('__custom_osrv_fetch__'.toJS);
  });

  test('defineCloudflareFetch validates the export name', () {
    expect(
      () => defineCloudflareFetch(
        Server(
          fetch: (request, context) => Response.text('ok'),
        ),
        name: ' ',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('defineCloudflareFetch bridges fetch into Server.fetch', () async {
    defineCloudflareFetch(
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

  test('defineCloudflareFetch forwards waitUntil to execution context', () async {
    final waitUntilCompleter = Completer<void>();
    final ctxExport = _TestExecutionContext();
    defineCloudflareFetch(
      Server(
        fetch: (request, context) {
          context.waitUntil(waitUntilCompleter.future);
          return Response.text('ok');
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

  test('defineCloudflareFetch uses onError to translate fetch failures', () async {
    defineCloudflareFetch(
      Server(
        fetch: (request, context) => throw StateError('boom'),
        onError: (error, stackTrace, context) {
          return Response.text(
            'handled ${context.runtime.name}',
            status: 418,
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
  });

  test('defineCloudflareFetch runs onStart only once', () async {
    var starts = 0;
    defineCloudflareFetch(
      Server(
        onStart: (context) {
          starts++;
        },
        fetch: (request, context) => Response.text('ok'),
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

  test('defineCloudflareFetch returns default 500 without onError', () async {
    defineCloudflareFetch(
      Server(
        fetch: (request, context) => throw StateError('boom'),
      ),
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

  test('defineCloudflareFetch respects a custom export name', () async {
    defineCloudflareFetch(
      Server(
        fetch: (request, context) => Response.text(request.url.path),
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
  return _fetchHandlerFor(defaultCloudflareFetchName);
}

JSFunction _fetchHandlerFor(String name) {
  return globalContext.getProperty<JSFunction?>(name.toJS)!;
}
