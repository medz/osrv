import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:osrv/osrv.dart';
import 'package:test/test.dart';

void main() {
  group('Server', () {
    test('serve and basic response', () async {
      final server = Server(port: 0, fetch: (request) => Response.text('ok'));

      await server.serve();

      final result = await _sendRequest(server.url, method: 'GET');
      expect(result.statusCode, 200);
      expect(result.body, 'ok');

      await server.close();
    });

    test('middleware chain onion order', () async {
      final trace = <String>[];
      final server = Server(
        port: 0,
        middleware: <Middleware>[
          (request, next) async {
            trace.add('m1-before');
            final response = await next(request);
            trace.add('m1-after');
            return response;
          },
          (request, next) async {
            trace.add('m2-before');
            final response = await next(request);
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
      await _sendRequest(server.url, method: 'GET');
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

    test('plugins lifecycle', () async {
      final plugin = _TracingPlugin();
      final server = Server(
        port: 0,
        plugins: <ServerPlugin>[plugin],
        fetch: (request) => Response.text('ok'),
      );

      await server.serve();
      await _sendRequest(server.url, method: 'GET');
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

    test('websocket upgrade and echo', () async {
      final server = Server(
        port: 0,
        fetch: (request) async {
          if (request.url.path != '/ws') {
            return Response.text('ok');
          }

          final socket = await upgradeWebSocket(request);
          unawaited(() async {
            await for (final message in socket.messages) {
              if (message is String) {
                await socket.sendText('echo:$message');
              }
            }
          }());
          return socket.toResponse();
        },
      );

      await server.serve();

      final wsScheme = server.url.scheme == 'https' ? 'wss' : 'ws';
      final wsUrl = Uri(
        scheme: wsScheme,
        host: server.url.host,
        port: server.url.port,
        path: '/ws',
      );

      final socket = await WebSocket.connect(wsUrl.toString());
      try {
        socket.add('hello');
        final message = await socket.first.timeout(const Duration(seconds: 3));
        expect(message, 'echo:hello');
      } finally {
        await socket.close();
      }

      await server.close();
    });

    test('request context/ip available', () async {
      final server = Server(
        port: 0,
        fetch: (request) {
          return Response.json(<String, Object?>{
            'ip': request.ip,
            'hasContext': request.context.isNotEmpty,
          });
        },
      );

      await server.serve();
      final result = await _sendRequest(server.url, method: 'GET');
      await server.close();

      final decoded = jsonDecode(result.body) as Map<String, Object?>;
      expect(decoded['ip'], isNotNull);
      expect(decoded['hasContext'], isTrue);
    });
  });
}

Future<_HttpResult> _sendRequest(
  Uri baseUrl, {
  required String method,
  String? body,
  Map<String, String>? headers,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, baseUrl);
    headers?.forEach(request.headers.set);
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
  Future<void> onRegister(ServerHandle server) async {
    hooks.add('register');
  }

  @override
  Future<void> onBeforeServe(ServerHandle server) async {
    hooks.add('beforeServe');
  }

  @override
  Future<void> onAfterServe(ServerHandle server) async {
    hooks.add('afterServe');
  }

  @override
  Future<void> onBeforeClose(ServerHandle server) async {
    hooks.add('beforeClose');
  }

  @override
  Future<void> onAfterClose(ServerHandle server) async {
    hooks.add('afterClose');
  }
}
