import '../../core/runtime.dart';
import '../../core/server.dart';
import 'config.dart';
import 'serve.dart';

Future<Runtime> serve(Server server, NodeRuntimeConfig config) {
  return serveNodeRuntime(server, config);
}
