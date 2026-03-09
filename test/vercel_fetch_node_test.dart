@TestOn('node')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/vercel.dart';
import 'package:osrv/src/runtime/_internal/js/web_stream_bridge.dart';
import 'package:osrv/src/runtime/vercel/host.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

const _defaultFetchExportName = '__osrv_fetch__';

void main() {
  tearDown(() {
    globalContext.delete(_defaultFetchExportName.toJS);
    globalContext.delete('__custom_osrv_fetch__'.toJS);
    globalContext.delete(defaultVercelFunctionsOverrideName.toJS);
    resetVercelFunctionHelpersCache();
  });

  test('defineFetchExport bridges fetch into Server.fetch', () async {
    defineFetchExport(
      Server(
        fetch: (request, context) {
          final vercel = context
              .extension<VercelRuntimeExtension<web.Request>>();
          final functions = vercel?.functions;

          return Response.json({
            'runtime': context.runtime.name,
            'path': request.url.path,
            'request': vercel?.request?.url ?? request.url.toString(),
            'streaming': context.capabilities.streaming,
            'backgroundTask': context.capabilities.backgroundTask,
            'nodeCompat': context.capabilities.nodeCompat,
            'websocket': context.capabilities.websocket,
            'region': (functions?.geolocation as Map?)?['region'],
            'env': (functions?.env as Map?)?['APP_ENV'],
            'ip': functions?.ipAddress,
            'hasFunctions': functions != null,
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
    expect(jsonDecode((await response.text().toDart).toDart), {
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
      'hasFunctions': true,
    });
  });

  test('defineFetchExport forwards waitUntil to helper bag', () async {
    final waitUntilCompleter = Completer<void>();
    final tracker = _TestWaitUntilTracker();

    defineFetchExport(
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

  test('defineFetchExport uses onError to translate failures', () async {
    defineFetchExport(
      Server(
        fetch: (request, context) => throw StateError('boom'),
        onError: (error, stackTrace, context) {
          return Response.text('handled ${context.runtime.name}', status: 418);
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

  test('defineFetchExport runs onStart only once', () async {
    var starts = 0;
    defineFetchExport(
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

  test('defineFetchExport returns default 500 without onError', () async {
    defineFetchExport(
      Server(fetch: (request, context) => throw StateError('boom')),
    );

    _installFunctionsOverride();
    final response = await _callVercelFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/unhandled'.toJS),
    );

    expect(response.status, 500);
    expect((await response.text().toDart).toDart, 'Internal Server Error');
  });

  test('defineFetchExport respects a custom export name', () async {
    defineFetchExport(
      Server(fetch: (request, context) => Response.text(request.url.path)),
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

  test('defineFetchExport does not pre-read the request stream', () async {
    final entered = Completer<void>();
    final body = StreamController<List<int>>();

    defineFetchExport(
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

  test('defineFetchExport returns a streaming response immediately', () async {
    final body = StreamController<List<int>>();

    defineFetchExport(
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

  test('defineFetchExport exposes cache and invalidation helpers', () async {
    final tracker = _TestWaitUntilTracker();

    defineFetchExport(
      Server(
        fetch: (request, context) async {
          final functions = context
              .extension<VercelRuntimeExtension<web.Request>>()!
              .functions!;
          final cache = functions.getCache(namespace: 'demo');

          await functions.invalidateByTag('tag-a', ['tag-b']);
          await functions.dangerouslyDeleteByTag(
            'tag-c',
            additionalTags: ['tag-d'],
            revalidationDeadlineSeconds: 10,
          );
          await functions.invalidateBySrcImage('/avatar.png');
          await functions.dangerouslyDeleteBySrcImage(
            '/cover.png',
            revalidationDeadlineSeconds: 20,
          );
          await functions.addCacheTag('product-1', ['products']);
          functions.attachDatabasePool(
            JSObject()..setProperty('id'.toJS, 'db'.toJS),
          );

          await cache.set(
            'answer',
            42,
            name: 'the answer',
            tags: ['math'],
            ttl: 60,
          );
          final cached = await cache.get('answer');
          await cache.expireTag('math');
          await cache.delete('answer');

          return Response.json({'cached': cached});
        },
      ),
    );

    _installFunctionsOverride(waitUntilTracker: tracker);
    final response = await _callVercelFetch(
      _currentFetchHandler(),
      web.Request('https://example.com/helpers'.toJS),
    );

    expect(response.status, 200);
    expect(jsonDecode((await response.text().toDart).toDart), {'cached': 42});

    final calls = _helperCalls();
    expect(calls['invalidateByTag'], [
      ['tag-a', 'tag-b'],
    ]);
    expect(calls['dangerouslyDeleteByTag'], [
      {
        'tags': ['tag-c', 'tag-d'],
        'revalidationDeadlineSeconds': 10,
      },
    ]);
    expect(calls['invalidateBySrcImage'], ['/avatar.png']);
    expect(calls['dangerouslyDeleteBySrcImage'], [
      {'srcImage': '/cover.png', 'revalidationDeadlineSeconds': 20},
    ]);
    expect(calls['addCacheTag'], [
      ['product-1', 'products'],
    ]);
    expect(calls['attachDatabasePool'], ['db']);
    expect(calls['getCache'], [
      {'namespace': 'demo', 'namespaceSeparator': null},
    ]);
    expect(calls['cacheSet'], [
      {
        'key': 'answer',
        'value': 42,
        'name': 'the answer',
        'tags': ['math'],
        'ttl': 60,
      },
    ]);
    expect(calls['cacheGet'], ['answer']);
    expect(calls['cacheExpireTag'], ['math']);
    expect(calls['cacheDelete'], ['answer']);
  });
}

final class _TestWaitUntilTracker {
  int waitUntilCalls = 0;
  final List<Future<JSAny?>> tasks = <Future<JSAny?>>[];
}

void _installFunctionsOverride({_TestWaitUntilTracker? waitUntilTracker}) {
  final tracker = waitUntilTracker ?? _TestWaitUntilTracker();
  final env = JSObject()..setProperty('APP_ENV'.toJS, 'test'.toJS);
  final geo = JSObject()..setProperty('region'.toJS, 'iad1'.toJS);
  final calls = JSObject()
    ..setProperty('invalidateByTag'.toJS, <Object?>[].jsify()!)
    ..setProperty('dangerouslyDeleteByTag'.toJS, <Object?>[].jsify()!)
    ..setProperty('invalidateBySrcImage'.toJS, <Object?>[].jsify()!)
    ..setProperty('dangerouslyDeleteBySrcImage'.toJS, <Object?>[].jsify()!)
    ..setProperty('addCacheTag'.toJS, <Object?>[].jsify()!)
    ..setProperty('attachDatabasePool'.toJS, <Object?>[].jsify()!)
    ..setProperty('getCache'.toJS, <Object?>[].jsify()!)
    ..setProperty('cacheGet'.toJS, <Object?>[].jsify()!)
    ..setProperty('cacheSet'.toJS, <Object?>[].jsify()!)
    ..setProperty('cacheDelete'.toJS, <Object?>[].jsify()!)
    ..setProperty('cacheExpireTag'.toJS, <Object?>[].jsify()!);
  final cacheStore = JSObject();

  final helpers = JSObject();
  helpers.setProperty(
    'waitUntil'.toJS,
    ((JSPromise<JSAny?> task) {
      tracker.waitUntilCalls++;
      tracker.tasks.add(task.toDart);
    }).toJS,
  );
  helpers.setProperty('getEnv'.toJS, (() => env).toJS);
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
  helpers.setProperty(
    'invalidateByTag'.toJS,
    ((JSAny tags) {
      _pushCall(calls, 'invalidateByTag', tags.dartify());
      return Future<void>.value().toJS;
    }).toJS,
  );
  helpers.setProperty(
    'dangerouslyDeleteByTag'.toJS,
    ((JSAny tags, [JSAny? options]) {
      final record = <String, Object?>{
        'tags': tags.dartify(),
        'revalidationDeadlineSeconds':
            (options?.dartify() as Map?)?['revalidationDeadlineSeconds'],
      };
      _pushCall(calls, 'dangerouslyDeleteByTag', record);
      return Future<void>.value().toJS;
    }).toJS,
  );
  helpers.setProperty(
    'invalidateBySrcImage'.toJS,
    ((JSString srcImage) {
      _pushCall(calls, 'invalidateBySrcImage', srcImage.toDart);
      return Future<void>.value().toJS;
    }).toJS,
  );
  helpers.setProperty(
    'dangerouslyDeleteBySrcImage'.toJS,
    ((JSString srcImage, [JSAny? options]) {
      final record = <String, Object?>{
        'srcImage': srcImage.toDart,
        'revalidationDeadlineSeconds':
            (options?.dartify() as Map?)?['revalidationDeadlineSeconds'],
      };
      _pushCall(calls, 'dangerouslyDeleteBySrcImage', record);
      return Future<void>.value().toJS;
    }).toJS,
  );
  helpers.setProperty(
    'addCacheTag'.toJS,
    ((JSAny tags) {
      _pushCall(calls, 'addCacheTag', tags.dartify());
      return Future<void>.value().toJS;
    }).toJS,
  );
  helpers.setProperty(
    'attachDatabasePool'.toJS,
    ((JSAny dbPool) {
      final record = (dbPool.dartify() as Map?)?['id'];
      _pushCall(calls, 'attachDatabasePool', record);
    }).toJS,
  );
  helpers.setProperty(
    'getCache'.toJS,
    (([JSAny? options]) {
      final values = (options?.dartify() as Map?) ?? const {};
      _pushCall(calls, 'getCache', {
        'namespace': values['namespace'],
        'namespaceSeparator': values['namespaceSeparator'],
      });

      final cache = JSObject();
      cache.setProperty(
        'get'.toJS,
        ((JSString key) {
          _pushCall(calls, 'cacheGet', key.toDart);
          return Future.value(cacheStore.getProperty<JSAny?>(key)).toJS;
        }).toJS,
      );
      cache.setProperty(
        'set'.toJS,
        ((JSString key, JSAny value, [JSAny? options]) {
          final dartValue = value.dartify();
          cacheStore.setProperty(key, value);
          final record = <String, Object?>{
            'key': key.toDart,
            'value': dartValue,
            'name': (options?.dartify() as Map?)?['name'],
            'tags': (options?.dartify() as Map?)?['tags'],
            'ttl': (options?.dartify() as Map?)?['ttl'],
          };
          _pushCall(calls, 'cacheSet', record);
          return Future<void>.value().toJS;
        }).toJS,
      );
      cache.setProperty(
        'delete'.toJS,
        ((JSString key) {
          cacheStore.delete(key);
          _pushCall(calls, 'cacheDelete', key.toDart);
          return Future<void>.value().toJS;
        }).toJS,
      );
      cache.setProperty(
        'expireTag'.toJS,
        ((JSAny tags) {
          _pushCall(calls, 'cacheExpireTag', tags.dartify());
          return Future<void>.value().toJS;
        }).toJS,
      );
      return cache;
    }).toJS,
  );
  globalContext.setProperty('__osrv_vercel_helper_calls__'.toJS, calls);
  globalContext.setProperty(defaultVercelFunctionsOverrideName.toJS, helpers);
}

JSExportedDartFunction _currentFetchHandler() =>
    _fetchHandlerFor(_defaultFetchExportName);

JSExportedDartFunction _fetchHandlerFor(String name) {
  return globalContext.getProperty<JSExportedDartFunction>(name.toJS);
}

Future<web.Response> _callVercelFetch(
  JSExportedDartFunction fetch,
  web.Request request,
) {
  return fetch.callMethodVarArgs<JSPromise<web.Response>>('call'.toJS, [
    null,
    request,
  ]).toDart;
}

Map<String, Object?> _helperCalls() {
  return (globalContext
              .getProperty<JSAny?>('__osrv_vercel_helper_calls__'.toJS)
              ?.dartify()
          as Map)
      .cast<String, Object?>();
}

void _pushCall(JSObject calls, String name, Object? value) {
  final list = calls.getProperty<JSArray>(name.toJS);
  list.callMethodVarArgs<JSAny?>('push'.toJS, [value.jsify()]);
}
