import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http2/http2.dart' as h2;
import 'package:osrv/osrv.dart';
import 'package:test/test.dart';

void main() {
  group('Server HTTP/2', () {
    test(
      'serves TLS requests over HTTP/2 with stable runtime context',
      () async {
        late final Server server;
        server = Server(
          port: 0,
          protocol: ServerProtocol.https,
          tls: const TlsOptions(
            cert: 'test/certificates/server_chain.pem',
            key: 'test/certificates/server_key.pem',
            passphrase: 'dartdart',
          ),
          fetch: (request) async {
            return Response.json(<String, Object?>{
              'runtime': request.runtime?.name,
              'httpVersion': request.runtime?.httpVersion,
              'protocol': request.runtime?.protocol,
            });
          },
        );

        await server.serve();
        expect(server.capabilities.http2, isTrue);
        expect(server.url, isNotNull);

        final uri = Uri.parse(server.url!);
        final response = await _sendHttp2Request(uri, path: '/h2');

        expect(response.statusCode, 200);
        final payload = jsonDecode(response.body) as Map<String, Object?>;
        expect(payload['runtime'], equals('dart'));
        expect(payload['httpVersion'], equals('2'));
        expect(payload['protocol'], equals('https'));

        await server.close();
      },
    );
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

    final responseHeaders = <String, String>{};
    final bodyBuffer = BytesBuilder(copy: false);

    await for (final message in stream.incomingMessages) {
      if (message is h2.HeadersStreamMessage) {
        for (final header in message.headers) {
          responseHeaders[_decodeHeaderBytes(header.name)] = _decodeHeaderBytes(
            header.value,
          );
        }
      } else if (message is h2.DataStreamMessage) {
        bodyBuffer.add(message.bytes);
      }
    }

    final statusCode = int.tryParse(responseHeaders[':status'] ?? '') ?? 500;
    final body = utf8.decode(bodyBuffer.takeBytes());
    return _Http2Result(statusCode: statusCode, body: body);
  } finally {
    await connection.finish();
  }
}

String _decodeHeaderBytes(List<int> bytes) {
  return utf8.decode(bytes, allowMalformed: true);
}

final class _Http2Result {
  const _Http2Result({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}
