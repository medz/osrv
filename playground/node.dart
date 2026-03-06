import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/node.dart';

import 'server.dart' as playground;

Future<void> main() async {
  final runtime = await serve(playground.server, const NodeRuntimeConfig());

  print('osrv playground (node) listening on ${runtime.url}');
  await runtime.closed;
}
