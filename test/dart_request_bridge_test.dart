@TestOn('vm')
library;

import 'dart:io';

import 'package:ht/ht.dart' show HttpMethod, Request;
import 'package:test/test.dart';

void main() {
  test('dart request bridge keeps HttpRequest host-backed semantics', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final port = server.port;

    final requestFuture = server.first;

    final client = HttpClient();
    addTearDown(client.close);

    final clientRequest = await client.post(
      InternetAddress.loopbackIPv4.host,
      port,
      '/upload?q=1',
    );
    clientRequest.headers.set('content-type', 'text/plain;charset=utf-8');
    clientRequest.headers.add('x-id', '1');
    clientRequest.write('hello world');
    final clientResponseFuture = clientRequest.close();

    final httpRequest = await requestFuture;
    final request = Request(httpRequest);
    final clone = request.clone();

    expect(request.method, HttpMethod.post);
    expect(request.url, 'http://127.0.0.1:$port/upload?q=1');
    expect(request.keepalive, isTrue);
    expect(request.headers.get('content-type'), 'text/plain;charset=utf-8');
    expect(request.headers.get('x-id'), '1');
    expect(request.bodyUsed, isFalse);
    expect(await request.text(), 'hello world');
    expect(await clone.text(), 'hello world');
    expect(request.bodyUsed, isTrue);

    httpRequest.response.statusCode = HttpStatus.noContent;
    await httpRequest.response.close();

    final clientResponse = await clientResponseFuture;
    await clientResponse.drain<void>();
  });
}
