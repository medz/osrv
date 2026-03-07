import 'package:osrv/osrv.dart';
import 'package:osrv/esm.dart';
import 'package:test/test.dart';

void main() {
  test('defineFetchEntry is explicit about requiring a JavaScript host', () {
    final server = Server(fetch: (request, context) => Response.text('ok'));

    expect(
      () => defineFetchEntry(server, runtime: FetchEntryRuntime.cloudflare),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('JavaScript host'),
        ),
      ),
    );
  });

  test('defineFetchEntry rejects an empty export name', () {
    final server = Server(fetch: (request, context) => Response.text('ok'));

    expect(
      () => defineFetchEntry(
        server,
        runtime: FetchEntryRuntime.cloudflare,
        name: '  ',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
