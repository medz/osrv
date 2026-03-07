import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/dart.dart';

import 'server.dart' as playground;

Future<void> main() async {
  final runtime = await serve(playground.server, const DartRuntimeConfig());

  print('osrv playground (dart) listening on ${runtime.url}');
  await runtime.closed;
}
