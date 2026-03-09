@TestOn('vm')
library;

import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/vercel.dart';
import 'package:test/test.dart';

void main() {
  test('defineFetchExport is explicit about requiring a JavaScript host', () {
    final server = Server(fetch: (request, context) => Response.text('ok'));

    expect(
      () => defineFetchExport(server),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('JavaScript host'),
        ),
      ),
    );
  });

  test('defineFetchExport rejects an empty export name', () {
    final server = Server(fetch: (request, context) => Response.text('ok'));

    expect(
      () => defineFetchExport(server, name: '  '),
      throwsA(isA<ArgumentError>()),
    );
  });
}
