import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/bun.dart';

import 'server.dart' as playground;

Future<void> main() async {
  final runtime = await serve(playground.server, const BunRuntimeConfig());

  print('osrv playground (bun) listening on ${runtime.url}');
  await runtime.closed;
}
