import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/bun.dart';

import 'server.dart' as example;

Future<void> main() async {
  final runtime = await serve(example.server, const BunRuntimeConfig());

  print('osrv example (bun) listening on ${runtime.url}');
  await runtime.closed;
}
