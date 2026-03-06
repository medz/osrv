import '../../core/runtime.dart';
import '../../core/server.dart';
import 'config.dart';
import 'preflight.dart';
import 'serve_host.dart';

Future<Runtime> serveBunRuntime(
  Server server,
  BunRuntimeConfig config,
) async {
  final preflight = preflightBunRuntime(config);
  if (!preflight.canServe) {
    throw preflight.toUnsupportedError();
  }

  return serveBunRuntimeHost(server, preflight);
}
