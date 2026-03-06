import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/cloudflare.dart';
import 'package:test/test.dart';

void main() {
  test('cloudflareWorker is explicit about requiring a JavaScript host', () {
    final server = Server(
      fetch: (request, context) => Response.text('ok'),
    );

    expect(
      () => cloudflareWorker(
        server,
        const CloudflareRuntimeConfig(),
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('JavaScript host'),
        ),
      ),
    );
  });
}
