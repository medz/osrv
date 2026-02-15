import 'dart:convert';
import 'dart:io';

import 'package:osrv/osrv.dart';
import 'package:test/test.dart';

void main() {
  group('Server', () {
    test('serve/ready/close lifecycle and basic response', () async {
      final server = Server(port: 0, fetch: (request) => Response.text('ok'));

      await server.serve();
      await server.ready();

      final result = await _sendRequest(server.url!, method: 'GET');
      expect(result.statusCode, 200);
      expect(result.body, 'ok');

      await server.close();
      expect(server.isServing, false);
    });

    test('middleware chain follows onion order', () async {
      final trace = <String>[];
      final server = Server(
        port: 0,
        middleware: <Middleware>[
          (request, next) async {
            trace.add('m1-before');
            final response = await next();
            trace.add('m1-after');
            return response;
          },
          (request, next) async {
            trace.add('m2-before');
            final response = await next();
            trace.add('m2-after');
            return response;
          },
        ],
        fetch: (request) async {
          trace.add('fetch');
          return Response.text('ok');
        },
      );

      await server.serve();
      await _sendRequest(server.url!, method: 'GET');
      await server.close();

      expect(
        trace,
        equals(<String>[
          'm1-before',
          'm2-before',
          'fetch',
          'm2-after',
          'm1-after',
        ]),
      );
    });

    test('plugins run full lifecycle hooks', () async {
      final plugin = _TracingPlugin();
      final server = Server(
        port: 0,
        plugins: <ServerPlugin>[plugin],
        fetch: (request) => Response.text('ok'),
      );

      await server.serve();
      await _sendRequest(server.url!, method: 'GET');
      await server.close();

      expect(
        plugin.hooks,
        containsAllInOrder(<String>[
          'register',
          'beforeServe',
          'afterServe',
          'beforeClose',
          'afterClose',
        ]),
      );
    });

    test('request runtime context exposes stable fields', () async {
      final server = Server(
        port: 0,
        fetch: (request) async {
          final runtime = request.runtime;
          final waitUntil = request.waitUntil;
          if (waitUntil != null) {
            waitUntil(Future<Object?>.value('done'));
          }

          return Response.json(<String, Object?>{
            'runtime': runtime?.name,
            'protocol': runtime?.protocol,
            'ip': request.ip,
            'contextReady': request.context.isEmpty,
          });
        },
      );

      await server.serve();
      final result = await _sendRequest(server.url!, method: 'GET');
      await server.close();

      final decoded = jsonDecode(result.body) as Map<String, Object?>;
      expect(decoded['runtime'], equals('dart'));
      expect(decoded['protocol'], isNotNull);
      expect(decoded['ip'], isNotNull);
    });

    test('default error response is safe in production mode', () async {
      final server = Server(
        port: 0,
        environment: const <String, String>{'OSRV_ENV': 'production'},
        fetch: (request) {
          throw StateError('boom');
        },
      );

      await server.serve();
      final result = await _sendRequest(server.url!, method: 'GET');
      await server.close();

      expect(result.statusCode, 500);
      final decoded = jsonDecode(result.body) as Map<String, Object?>;
      expect(decoded['details'], isNull);
      expect(decoded['error'], equals('Internal Server Error'));
    });

    test('request body limit returns 413', () async {
      final server = Server(
        port: 0,
        securityLimits: const ServerSecurityLimits(maxRequestBodyBytes: 4),
        fetch: (request) async {
          final body = await request.text();
          return Response.text(body);
        },
      );

      await server.serve();
      final result = await _sendRequest(
        server.url!,
        method: 'POST',
        body: '1234567890',
      );
      await server.close();

      expect(result.statusCode, 413);
      final decoded = jsonDecode(result.body) as Map<String, Object?>;
      expect(decoded['error'], equals('Request body too large'));
    });
  });
}

Future<_HttpResult> _sendRequest(
  String baseUrl, {
  required String method,
  String? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse(baseUrl));
    if (body != null) {
      request.write(body);
    }
    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);
    return _HttpResult(response.statusCode, responseBody);
  } finally {
    client.close(force: true);
  }
}

final class _HttpResult {
  const _HttpResult(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

final class _TracingPlugin extends ServerPlugin {
  final List<String> hooks = <String>[];

  @override
  Future<void> onRegister(RegisterPluginContext context) async {
    hooks.add('register');
  }

  @override
  Future<void> onBeforeServe(BeforeServePluginContext context) async {
    hooks.add('beforeServe');
  }

  @override
  Future<void> onAfterServe(AfterServePluginContext context) async {
    hooks.add('afterServe');
  }

  @override
  Future<void> onBeforeClose(BeforeClosePluginContext context) async {
    hooks.add('beforeClose');
  }

  @override
  Future<void> onAfterClose(AfterClosePluginContext context) async {
    hooks.add('afterClose');
  }
}
