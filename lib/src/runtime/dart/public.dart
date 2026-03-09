import '../../core/runtime.dart';
import '../../core/server.dart';
import 'serve.dart';

/// Starts a native Dart listener runtime for [server].
Future<Runtime> serve(
  Server server, {
  String host = '127.0.0.1',
  int port = 3000,
  int backlog = 0,
  bool shared = false,
  bool v6Only = false,
}) {
  return serveDartRuntime(
    server,
    host: host,
    port: port,
    backlog: backlog,
    shared: shared,
    v6Only: v6Only,
  );
}
