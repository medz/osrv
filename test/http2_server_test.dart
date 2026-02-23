import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http2/http2.dart' as h2;
import 'package:osrv/osrv.dart';
import 'package:test/test.dart';

void main() {
  test('serves TLS over HTTP/2', () async {
    final server = Server(
      port: 0,
      protocol: HTTPProtocol.https,
      tls: const TLSOptions(
        cert: 'test/certificates/server_cert.pem',
        key: 'test/certificates/server_key.pem',
      ),
      http2: true,
      fetch: (request) async {
        return Response.json(<String, Object?>{
          'runtime': 'dart:io',
          'path': request.url.path,
        });
      },
    );

    await server.serve();
    final result = await _sendHttp2Request(server.url, path: '/h2');
    await server.close();

    expect(result.statusCode, 200);
    final payload = jsonDecode(result.body) as Map<String, Object?>;
    expect(payload['runtime'], 'dart:io');
    expect(payload['path'], '/h2');
  });
}

Future<_Http2Result> _sendHttp2Request(
  Uri origin, {
  required String path,
}) async {
  final socket = await SecureSocket.connect(
    origin.host,
    origin.port,
    onBadCertificate: (_) => true,
    supportedProtocols: const <String>['h2', 'http/1.1'],
  );

  final connection = h2.ClientTransportConnection.viaSocket(socket);
  try {
    final stream = connection.makeRequest(<h2.Header>[
      h2.Header.ascii(':method', 'GET'),
      h2.Header.ascii(':scheme', origin.scheme),
      h2.Header.ascii(':authority', '${origin.host}:${origin.port}'),
      h2.Header.ascii(':path', path),
    ], endStream: true);

    final headers = <String, String>{};
    final bodyBuffer = BytesBuilder(copy: false);

    await for (final message in stream.incomingMessages) {
      if (message is h2.HeadersStreamMessage) {
        for (final header in message.headers) {
          headers[_decode(header.name)] = _decode(header.value);
        }
      } else if (message is h2.DataStreamMessage) {
        bodyBuffer.add(message.bytes);
      }
    }

    final statusCode = int.tryParse(headers[':status'] ?? '') ?? 500;
    final body = utf8.decode(bodyBuffer.takeBytes());
    return _Http2Result(statusCode: statusCode, body: body);
  } finally {
    await connection.finish();
  }
}

String _decode(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

final class _Http2Result {
  const _Http2Result({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}
