import 'package:osrv/runtime/deno.dart';

import 'server.dart' as example;

Future<void> main() async {
  final runtime = await serve(example.server);

  print('osrv example (deno) listening on ${runtime.url}');
  await runtime.closed;
}
