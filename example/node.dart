import 'package:osrv/runtime/node.dart';

import 'server.dart' as example;

Future<void> main() async {
  final runtime = await serve(example.server);

  print('osrv example (node) listening on ${runtime.url}');
  await runtime.closed;
}
