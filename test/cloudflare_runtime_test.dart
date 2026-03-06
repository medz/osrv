import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/cloudflare.dart';
import 'package:test/test.dart';

void main() {
  test('defineCloudflareFetch is explicit about requiring a JavaScript host', () {
    final server = Server(
      fetch: (request, context) => Response.text('ok'),
    );

    expect(
      () => defineCloudflareFetch(server),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('JavaScript host'),
        ),
      ),
    );
  });

  test('defineCloudflareFetch rejects an empty export name', () {
    final server = Server(
      fetch: (request, context) => Response.text('ok'),
    );

    expect(
      () => defineCloudflareFetch(server, name: '  '),
      throwsA(isA<ArgumentError>()),
    );
  });
}
