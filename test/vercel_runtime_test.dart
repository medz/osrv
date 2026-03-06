import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/vercel.dart';
import 'package:test/test.dart';

void main() {
  test('defineVercelFetch is explicit about requiring a JavaScript host', () {
    final server = Server(
      fetch: (request, context) => Response.text('ok'),
    );

    expect(
      () => defineVercelFetch(server),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('JavaScript host'),
        ),
      ),
    );
  });

  test('defineVercelFetch rejects an empty export name', () {
    final server = Server(
      fetch: (request, context) => Response.text('ok'),
    );

    expect(
      () => defineVercelFetch(server, name: '  '),
      throwsA(isA<ArgumentError>()),
    );
  });
}
