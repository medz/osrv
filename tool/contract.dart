import 'dart:convert';
import 'dart:io';

import 'package:osrv/osrv.dart';

Future<void> main() async {
  final report = <String, Object?>{};

  final server = Server(
    port: 0,
    hostname: '127.0.0.1',
    silent: true,
    middleware: <Middleware>[
      (request, next) async {
        request.context['trace'] = 'mw';
        final response = await next();
        response.headers.set('x-contract', '1');
        return response;
      },
    ],
    fetch: (request) async {
      if (request.url.path == '/error') {
        throw StateError('forced error');
      }

      if (request.url.path == '/echo') {
        return Response.text(await request.text());
      }

      return Response.json(<String, Object?>{
        'runtime': request.runtime?.name,
        'path': request.url.path,
      });
    },
  );

  await server.serve();
  final baseUrl = server.url!;

  report['runtime'] = server.runtime;
  report['capabilities'] = server.capabilities.toJson();

  final getResult = await _request(baseUrl, 'GET', '/');
  final postResult = await _request(baseUrl, 'POST', '/echo', body: 'hello');
  final errorResult = await _request(baseUrl, 'GET', '/error');

  report['scenarios'] = <String, Object?>{
    'get': <String, Object?>{
      'status': getResult.status,
      'header': getResult.headers['x-contract'],
      'body': jsonDecode(getResult.body),
    },
    'post': <String, Object?>{
      'status': postResult.status,
      'body': postResult.body,
    },
    'error': <String, Object?>{
      'status': errorResult.status,
      'body': jsonDecode(errorResult.body),
    },
  };

  await server.close();

  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}

Future<_ResponseData> _request(
  String baseUrl,
  String method,
  String path, {
  String? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse('$baseUrl$path'));
    if (body != null) {
      request.write(body);
    }

    final response = await request.close();
    final text = await utf8.decodeStream(response);
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });

    return _ResponseData(response.statusCode, text, headers);
  } finally {
    client.close(force: true);
  }
}

final class _ResponseData {
  const _ResponseData(this.status, this.body, this.headers);

  final int status;
  final String body;
  final Map<String, String> headers;
}
