@TestOn('node')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/netlify.dart';
import 'package:osrv/src/runtime/_internal/js/web_stream_bridge.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

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
          final netlify = context
              .extension<NetlifyRuntimeExtension<web.Request>>();
          final uri = Uri.parse(request.url);
          final params = netlify?.context?.params as Map?;

          return Response.json({
            'runtime': context.runtime.name,
            'path': uri.path,
            'request': netlify?.request?.url ?? request.url,
            'streaming': context.capabilities.streaming,
            'backgroundTask': context.capabilities.backgroundTask,
            'nodeCompat': context.capabilities.nodeCompat,
            'websocket': context.capabilities.websocket,
            'hasWebSocket': context.webSocket != null,
            'ip': netlify?.context?.ip,
            'requestId': netlify?.context?.requestId,
            'slug': params?['slug'],
            'hasSite': netlify?.context?.site != null,
            'hasAccount': netlify?.context?.account != null,
          });
        },
      ),
    );

    final response = await _callNetlifyFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/hello'.toJS),
      _createNetlifyContext(),
    );

    expect(response.status, 200);
    expect(jsonDecode((await response.text().toDart).toDart), {
      'runtime': 'netlify',
      'path': '/hello',
      'request': 'https://example.com/hello',
      'streaming': true,
      'backgroundTask': true,
      'nodeCompat': true,
      'websocket': false,
      'hasWebSocket': false,
      'ip': '127.0.0.1',
      'requestId': 'req-123',
      'slug': 'hello',
      'hasSite': true,
      'hasAccount': true,
    });
  });

  test('defineFetchExport forwards waitUntil to function context', () async {
    final waitUntilCompleter = Completer<void>();
    final tracker = _TestWaitUntilTracker();

    defineFetchExport(
      Server(
        fetch: (request, context) {
          context.waitUntil(waitUntilCompleter.future);
          return Response('ok');
        },
      ),
    );

    final response = await _callNetlifyFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/wait'.toJS),
      _createNetlifyContext(waitUntilTracker: tracker),
    );

    expect(response.status, 200);
    expect(tracker.waitUntilCalls, 1);

    waitUntilCompleter.complete();
    await Future.wait(tracker.tasks);
  });

  test(
    'defineFetchExport keeps websocket request surface unavailable on upgrade-like requests',
    () async {
      defineFetchExport(
        Server(
          fetch: (request, context) {
            return Response.json({
              'websocket': context.capabilities.websocket,
              'hasWebSocket': context.webSocket != null,
            });
          },
        ),
      );

      final headers = web.Headers();
      headers.set('upgrade', 'websocket');
      headers.set('connection', 'Upgrade');
      headers.set('sec-websocket-protocol', 'chat');

      final response = await _callNetlifyFetch(
        _currentFetchHandler(),
        web.Request(
          'https://example.com/chat'.toJS,
          web.RequestInit(headers: headers),
        ),
        _createNetlifyContext(),
      );

      expect(response.status, 200);
      expect(jsonDecode((await response.text().toDart).toDart), {
        'websocket': false,
        'hasWebSocket': false,
      });
    },
  );

  test('defineFetchExport uses onError to translate failures', () async {
    defineFetchExport(
      Server(
        fetch: (request, context) => throw StateError('boom'),
        onError: (error, stackTrace, context) {
          return Response(
            'handled ${context.runtime.name}',
            ResponseInit(status: 418),
          );
        },
      ),
    );

    final response = await _callNetlifyFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/error'.toJS),
      _createNetlifyContext(),
    );

    expect(response.status, 418);
    expect((await response.text().toDart).toDart, 'handled netlify');
  });

  test('defineFetchExport runs onStart only once', () async {
    var starts = 0;
    NetlifyRuntimeExtension<web.Request>? startExtension;
    defineFetchExport(
      Server(
        onStart: (context) {
          starts++;
          startExtension = context
              .extension<NetlifyRuntimeExtension<web.Request>>();
        },
        fetch: (request, context) => Response('ok'),
      ),
    );

    final first = await _callNetlifyFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/one'.toJS),
      _createNetlifyContext(),
    );
    final second = await _callNetlifyFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/two'.toJS),
      _createNetlifyContext(),
    );

    expect(first.status, 200);
    expect(second.status, 200);
    expect(starts, 1);
    expect(startExtension?.request, isNull);
    expect(startExtension?.context, isNull);
  });

  test(
    'defineFetchExport reports backgroundTask false without waitUntil',
    () async {
      defineFetchExport(
        Server(
          fetch: (request, context) {
            return Response.json({
              'backgroundTask': context.capabilities.backgroundTask,
            });
          },
        ),
      );

      final context = _createNetlifyContext()..delete('waitUntil'.toJS);
      final response = await _callNetlifyFetch(
        _currentFetchHandler(),
        web.Request('https://example.com/background-task'.toJS),
        context,
      );

      expect(response.status, 200);
      expect(jsonDecode((await response.text().toDart).toDart), {
        'backgroundTask': false,
      });
    },
  );

  test('defineFetchExport returns default 500 without onError', () async {
    defineFetchExport(
      Server(fetch: (request, context) => throw StateError('boom')),
    );

    final response = await _callNetlifyFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/unhandled'.toJS),
      _createNetlifyContext(),
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

      final response = await _callNetlifyFetch(
        _currentFetchHandler(),
        web.Request('https://example.com/raw-101'.toJS),
        _createNetlifyContext(),
      );

      expect(response.status, 500);
      expect((await response.text().toDart).toDart, 'Internal Server Error');
    },
  );

  test('defineFetchExport rejects raw 101 responses from onError', () async {
    defineFetchExport(
      Server(
        fetch: (request, context) => throw StateError('boom'),
        onError: (error, stackTrace, context) {
          return Response(null, const ResponseInit(status: 101));
        },
      ),
    );

    final response = await _callNetlifyFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/raw-101-error'.toJS),
      _createNetlifyContext(),
    );

    expect(response.status, 500);
    expect((await response.text().toDart).toDart, 'Internal Server Error');
  });

  test('defineFetchExport preserves Response.error semantics', () async {
    defineFetchExport(Server(fetch: (request, context) => Response.error()));

    final response = await _callNetlifyFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/error-response'.toJS),
      _createNetlifyContext(),
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

    final response = await _callNetlifyFetch(
      _fetchHandlerFor('__custom_osrv_fetch__'),
      web.Request('https://example.com/custom'.toJS),
      _createNetlifyContext(),
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

    final responseFuture = _callNetlifyFetch(
      _currentFetchHandler(),
      web.Request(
        'https://example.com/stream-request'.toJS,
        web.RequestInit(
          method: 'POST',
          body: webReadableStreamFromDartByteStream(body.stream),
          duplex: 'half',
        ),
      ),
      _createNetlifyContext(),
    );

    await entered.future.timeout(const Duration(seconds: 2));

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

    final responseFuture = _callNetlifyFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/stream-response'.toJS),
      _createNetlifyContext(),
    );

    final response = await responseFuture.timeout(const Duration(seconds: 2));

    expect(response.status, 200);
    expect(response.headers.get('content-type'), 'text/plain');

    body.add(utf8.encode('hello '));
    body.add(utf8.encode('netlify'));
    await body.close();

    expect((await response.text().toDart).toDart, 'hello netlify');
  });
}

final class _TestWaitUntilTracker {
  int waitUntilCalls = 0;
  final List<Future<JSAny?>> tasks = <Future<JSAny?>>[];
}

JSObject _createNetlifyContext({_TestWaitUntilTracker? waitUntilTracker}) {
  final tracker = waitUntilTracker ?? _TestWaitUntilTracker();
  final context = JSObject()
    ..setProperty(
      'account'.toJS,
      JSObject()..setProperty('id'.toJS, 'acct-1'.toJS),
    )
    ..setProperty('cookies'.toJS, JSObject())
    ..setProperty(
      'deploy'.toJS,
      JSObject()..setProperty('id'.toJS, 'deploy-1'.toJS),
    )
    ..setProperty(
      'geo'.toJS,
      JSObject()..setProperty('city'.toJS, 'Hangzhou'.toJS),
    )
    ..setProperty('ip'.toJS, '127.0.0.1'.toJS)
    ..setProperty('params'.toJS, <String, Object?>{'slug': 'hello'}.jsify()!)
    ..setProperty('requestId'.toJS, 'req-123'.toJS)
    ..setProperty(
      'server'.toJS,
      JSObject()..setProperty('region'.toJS, 'us-east-1'.toJS),
    )
    ..setProperty(
      'site'.toJS,
      JSObject()..setProperty('name'.toJS, 'demo'.toJS),
    )
    ..setProperty(
      'waitUntil'.toJS,
      ((JSPromise<JSAny?> task) {
        tracker.waitUntilCalls++;
        tracker.tasks.add(task.toDart);
      }).toJS,
    );

  return context;
}

JSExportedDartFunction _currentFetchHandler() =>
    _fetchHandlerFor(_defaultFetchExportName);

JSExportedDartFunction _fetchHandlerFor(String name) {
  return globalContext.getProperty<JSExportedDartFunction>(name.toJS);
}

Future<web.Response> _callNetlifyFetch(
  JSExportedDartFunction fetch,
  web.Request request,
  JSObject context,
) {
  return fetch.callMethodVarArgs<JSPromise<web.Response>>('call'.toJS, [
    null,
    request,
    context,
  ]).toDart;
}
