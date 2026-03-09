import '../../core/runtime.dart';
import '../../core/server.dart';
import 'serve.dart';

/// Starts the Bun runtime for [server].
Future<Runtime> serve(
  Server server, {
  String host = '127.0.0.1',
  int port = 3000,
}) {
  return serveBunRuntime(server, host: host, port: port);
}
