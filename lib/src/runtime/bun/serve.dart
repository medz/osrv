// ignore_for_file: public_member_api_docs

import '../../core/runtime.dart';
import '../../core/server.dart';
import 'preflight.dart';
import 'serve_host.dart';

Future<Runtime> serveBunRuntime(
  Server server, {
  String host = '127.0.0.1',
  int port = 3000,
}) async {
  final preflight = preflightBunRuntime(host: host, port: port);
  if (!preflight.canServe) {
    throw preflight.toUnsupportedError();
  }

  return serveBunRuntimeHost(server, preflight);
}
