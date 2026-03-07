import '../../core/runtime.dart';
import '../../core/server.dart';
import 'preflight.dart';

Future<Runtime> serveBunRuntimeHost(
  Server server,
  BunRuntimePreflight preflight,
) {
  server;
  throw preflight.toUnsupportedError();
}
