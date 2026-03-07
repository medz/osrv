import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/dart.dart';

import 'server.dart' as example;

Future<void> main() async {
  final runtime = await serve(example.server, const DartRuntimeConfig());

  print('osrv example (dart) listening on ${runtime.url}');
  await runtime.closed;
}
