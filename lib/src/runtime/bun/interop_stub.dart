// ignore_for_file: public_member_api_docs

final class BunHostObject {
  const BunHostObject();
}

final class BunGlobal {
  const BunGlobal({this.version, this.serve});

  final String? version;
  final Object? serve;
}

BunHostObject? get globalThis => null;

BunGlobal? get bunGlobal => null;

String? bunVersion(BunGlobal bun) => bun.version;

bool bunHasServe(BunGlobal bun) => bun.serve != null;

final class BunServerHost {
  const BunServerHost({this.port});

  final int? port;
}

BunServerHost bunServe(
  BunGlobal bun, {
  required String host,
  required int port,
  required Object fetch,
}) {
  bun;
  host;
  port;
  fetch;
  throw UnsupportedError('Bun.serve is unavailable on the current host.');
}

int? bunServerPort(BunServerHost server) => server.port;

Future<void> stopBunServer(BunServerHost server, {bool force = false}) async {
  server;
  force;
}
