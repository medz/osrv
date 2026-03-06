@TestOn('node')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/vercel.dart';
import 'package:osrv/src/runtime/vercel/stream_bridge.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  tearDown(() {
    globalContext.delete(defaultVercelFetchName.toJS);
    globalContext.delete('__custom_osrv_fetch__'.toJS);
    globalContext.delete(defaultVercelFunctionsOverrideName.toJS);
    resetVercelFunctionHelpersCache();
  });

  test('defineVercelFetch bridges fetch into Server.fetch', () async {
    defineVercelFetch(
      Server(
        fetch: (request, context) {
          final vercel = context.extension<
              VercelRuntimeExtension<VercelFunctionHelpersHost, web.Request>>();

          return Response.json({
            'runtime': context.runtime.name,
            'path': request.url.path,
            'request': vercel?.request?.url ?? request.url.toString(),
            'streaming': context.capabilities.streaming,
            'backgroundTask': context.capabilities.backgroundTask,
            'nodeCompat': context.capabilities.nodeCompat,
            'websocket': context.capabilities.websocket,
            'region': (vercel?.geolocation as Map?)?['region'],
            'env': (vercel?.env as Map?)?['APP_ENV'],
            'ip': vercel?.ipAddress,
          });
        },
      ),
    );

    _installFunctionsOverride();
    final response = await _callVercelFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/hello'.toJS),
    );

    expect(response.status, 200);
    expect(
      jsonDecode((await response.text().toDart).toDart),
      {
        'runtime': 'vercel',
        'path': '/hello',
        'request': 'https://example.com/hello',
        'streaming': true,
        'backgroundTask': true,
        'nodeCompat': true,
        'websocket': false,
        'region': 'iad1',
        'env': 'test',
        'ip': '127.0.0.1',
      },
    );
  });

  test('defineVercelFetch forwards waitUntil to helper bag', () async {
    final waitUntilCompleter = Completer<void>();
    final tracker = _TestWaitUntilTracker();

    defineVercelFetch(
      Server(
        fetch: (request, context) {
          context.waitUntil(waitUntilCompleter.future);
          return Response.text('ok');
        },
      ),
    );

    _installFunctionsOverride(waitUntilTracker: tracker);
    final response = await _callVercelFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/wait'.toJS),
    );

    expect(response.status, 200);
    expect(tracker.waitUntilCalls, 1);

    waitUntilCompleter.complete();
    await Future.wait(tracker.tasks);
  });

  test('defineVercelFetch uses onError to translate failures', () async {
    defineVercelFetch(
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

    _installFunctionsOverride();
    final response = await _callVercelFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/error'.toJS),
    );

    expect(response.status, 418);
    expect((await response.text().toDart).toDart, 'handled vercel');
  });

  test('defineVercelFetch runs onStart only once', () async {
    var starts = 0;
    defineVercelFetch(
      Server(
        onStart: (context) {
          starts++;
        },
        fetch: (request, context) => Response.text('ok'),
      ),
    );

    _installFunctionsOverride();
    final first = await _callVercelFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/one'.toJS),
    );
    final second = await _callVercelFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/two'.toJS),
    );

    expect(first.status, 200);
    expect(second.status, 200);
    expect(starts, 1);
  });

  test('defineVercelFetch returns default 500 without onError', () async {
    defineVercelFetch(
      Server(
        fetch: (request, context) => throw StateError('boom'),
      ),
    );

    _installFunctionsOverride();
    final response = await _callVercelFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/unhandled'.toJS),
    );

    expect(response.status, 500);
    expect((await response.text().toDart).toDart, 'Internal Server Error');
  });

  test('defineVercelFetch respects a custom export name', () async {
    defineVercelFetch(
      Server(
        fetch: (request, context) => Response.text(request.url.path),
      ),
      name: '__custom_osrv_fetch__',
    );

    _installFunctionsOverride();
    final response = await _callVercelFetch(
      _fetchHandlerFor('__custom_osrv_fetch__'),
      web.Request('https://example.com/custom'.toJS),
    );

    expect(response.status, 200);
    expect((await response.text().toDart).toDart, '/custom');
  });

  test('defineVercelFetch does not pre-read the request stream', () async {
    final entered = Completer<void>();
    final body = StreamController<List<int>>();

    defineVercelFetch(
      Server(
        fetch: (request, context) {
          entered.complete();
          return Response.text(request.method);
        },
      ),
    );

    _installFunctionsOverride();
    final responseFuture = _callVercelFetch(
      _currentFetchHandler(),
      web.Request(
        'https://example.com/stream-request'.toJS,
        web.RequestInit(
          method: 'POST',
          body: webReadableStreamFromDartByteStream(body.stream),
          duplex: 'half',
        ),
      ),
    );

    await entered.future.timeout(const Duration(milliseconds: 250));

    body.add(utf8.encode('chunk'));
    await body.close();

    final response = await responseFuture;
    expect(response.status, 200);
    expect((await response.text().toDart).toDart, 'POST');
  });

  test('defineVercelFetch returns a streaming response immediately', () async {
    final body = StreamController<List<int>>();

    defineVercelFetch(
      Server(
        fetch: (request, context) {
          return Response(
            body: body.stream,
            headers: Headers()..set('content-type', 'text/plain'),
          );
        },
      ),
    );

    _installFunctionsOverride();
    final responseFuture = _callVercelFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/stream-response'.toJS),
    );

    final response = await responseFuture.timeout(
      const Duration(milliseconds: 250),
    );

    expect(response.status, 200);
    expect(response.headers.get('content-type'), 'text/plain');

    body.add(utf8.encode('hello '));
    body.add(utf8.encode('vercel'));
    await body.close();

    expect((await response.text().toDart).toDart, 'hello vercel');
  });
}

final class _TestWaitUntilTracker {
  int waitUntilCalls = 0;
  final List<Future<JSAny?>> tasks = <Future<JSAny?>>[];
}

void _installFunctionsOverride({
  _TestWaitUntilTracker? waitUntilTracker,
}) {
  final tracker = waitUntilTracker ?? _TestWaitUntilTracker();
  final env = JSObject()..setProperty('APP_ENV'.toJS, 'test'.toJS);
  final geo = JSObject()..setProperty('region'.toJS, 'iad1'.toJS);

  final helpers = JSObject();
  helpers.setProperty(
    'waitUntil'.toJS,
    ((JSPromise<JSAny?> task) {
      tracker.waitUntilCalls++;
      tracker.tasks.add(task.toDart);
    }).toJS,
  );
  helpers.setProperty(
    'getEnv'.toJS,
    (() => env).toJS,
  );
  helpers.setProperty(
    'geolocation'.toJS,
    ((web.Request request) {
      request;
      return geo;
    }).toJS,
  );
  helpers.setProperty(
    'ipAddress'.toJS,
    ((web.Request request) {
      request;
      return '127.0.0.1';
    }).toJS,
  );
  globalContext.setProperty(
    defaultVercelFunctionsOverrideName.toJS,
    helpers,
  );
}

JSExportedDartFunction _currentFetchHandler() =>
    _fetchHandlerFor(defaultVercelFetchName);

JSExportedDartFunction _fetchHandlerFor(String name) {
  return globalContext.getProperty<JSExportedDartFunction>(name.toJS);
}

Future<web.Response> _callVercelFetch(
  JSExportedDartFunction fetch,
  web.Request request,
) {
  return fetch
      .callMethodVarArgs<JSPromise<web.Response>>(
        'call'.toJS,
        [null, request],
      )
      .toDart;
}
