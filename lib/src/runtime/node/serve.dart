import '../../core/runtime.dart';
import '../../core/server.dart';
import 'config.dart';
import 'preflight.dart';
import 'serve_host.dart';

Future<Runtime> serveNodeRuntime(
  Server server,
  NodeRuntimeConfig config,
) async {
  final preflight = preflightNodeRuntime(config);
  if (!preflight.canServe) {
    throw preflight.toUnsupportedError();
  }

  return serveNodeRuntimeHost(server, preflight);
}
