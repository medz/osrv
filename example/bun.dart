import 'package:osrv/runtime/bun.dart';

import 'server.dart' as example;

Future<void> main() async {
  final runtime = await serve(example.server);

  print('osrv example (bun) listening on ${runtime.url}');
  await runtime.closed;
}
