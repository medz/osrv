import '../../core/runtime.dart';
import '../../core/server.dart';
import 'config.dart';
import 'preflight.dart';

Future<Runtime> serveBunRuntime(
  Server server,
  BunRuntimeConfig config,
) async {
  server;
  final preflight = preflightBunRuntime(config);
  throw preflight.toUnsupportedError();
}
