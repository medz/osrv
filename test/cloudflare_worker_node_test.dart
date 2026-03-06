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
  test('cloudflare worker validates config before exporting', () {
    expect(
      () => cloudflareWorker(
        Server(
          fetch: (request, context) => Response.text('ok'),
        ),
        const CloudflareRuntimeConfig(enableFetch: false),
      ),
      throwsA(
        isA<RuntimeConfigurationError>().having(
          (error) => error.message,
          'message',
          contains('enableFetch must be true'),
        ),
      ),
    );
  });

  test('cloudflare worker bridges fetch into Server.fetch', () async {
    final worker = cloudflareWorker(
      Server(
        fetch: (request, context) {
          final cf = context.extension<CloudflareRuntimeExtension>();
          final env = cf?.env as JSObject?;
          final name = env?.getProperty<JSString?>('name'.toJS)?.toDart;

          return Response.json({
            'runtime': context.runtime.name,
            'path': request.url.path,
            'name': name,
          });
        },
      ),
      const CloudflareRuntimeConfig(),
    ) as JSObject;

    final env = JSObject()..setProperty('name'.toJS, 'worker'.toJS);
    final ctx = createJSInteropWrapper(_TestExecutionContext());
    final response = await _callWorkerFetch(
      worker,
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
        'name': 'worker',
      },
    );
  });

  test('cloudflare worker forwards waitUntil to execution context', () async {
    final waitUntilCompleter = Completer<void>();
    final ctxExport = _TestExecutionContext();
    final worker = cloudflareWorker(
      Server(
        fetch: (request, context) {
          context.waitUntil(waitUntilCompleter.future);
          return Response.text('ok');
        },
      ),
      const CloudflareRuntimeConfig(),
    ) as JSObject;

    final response = await _callWorkerFetch(
      worker,
      web.Request('https://example.com/wait'.toJS),
      JSObject(),
      createJSInteropWrapper(ctxExport),
    );

    expect(response.status, 200);
    expect(ctxExport.waitUntilCalls, 1);

    waitUntilCompleter.complete();
    await Future.wait(ctxExport.tasks);
  });

  test('cloudflare worker uses onError to translate fetch failures', () async {
    final worker = cloudflareWorker(
      Server(
        fetch: (request, context) => throw StateError('boom'),
        onError: (error, stackTrace, context) {
          return Response.text(
            'handled ${context.runtime.name}',
            status: 418,
          );
        },
      ),
      const CloudflareRuntimeConfig(),
    ) as JSObject;

    final response = await _callWorkerFetch(
      worker,
      web.Request('https://example.com/error'.toJS),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );

    expect(response.status, 418);
    expect((await response.text().toDart).toDart, 'handled cloudflare');
  });

  test('cloudflare worker runs onStart only once', () async {
    var starts = 0;
    final worker = cloudflareWorker(
      Server(
        onStart: (context) {
          starts++;
        },
        fetch: (request, context) => Response.text('ok'),
      ),
      const CloudflareRuntimeConfig(),
    ) as JSObject;

    final first = await _callWorkerFetch(
      worker,
      web.Request('https://example.com/one'.toJS),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );
    final second = await _callWorkerFetch(
      worker,
      web.Request('https://example.com/two'.toJS),
      JSObject(),
      createJSInteropWrapper(_TestExecutionContext()),
    );

    expect(first.status, 200);
    expect(second.status, 200);
    expect(starts, 1);
  });

  test('cloudflare worker returns default 500 without onError', () async {
    final worker = cloudflareWorker(
      Server(
        fetch: (request, context) => throw StateError('boom'),
      ),
      const CloudflareRuntimeConfig(),
    ) as JSObject;

    final response = await _callWorkerFetch(
      worker,
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
}

Future<web.Response> _callWorkerFetch(
  JSObject worker,
  web.Request request,
  JSObject env,
  JSObject ctx,
) {
  return worker
      .callMethodVarArgs<JSPromise<web.Response>>(
        'fetch'.toJS,
        [request, env, ctx],
      )
      .toDart;
}
