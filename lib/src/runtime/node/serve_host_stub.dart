import '../../core/runtime.dart';
import '../../core/server.dart';
import 'preflight.dart';

Future<Runtime> serveNodeRuntimeHost(
  Server server,
  NodeRuntimePreflight preflight,
) async {
  server;
  throw preflight.toUnsupportedError();
}
