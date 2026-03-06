import 'runtime.dart';
import 'runtime_config.dart';
import 'server.dart';
import '../runtime/bun/config.dart';
import '../runtime/bun/serve.dart';
import '../runtime/dart/config.dart';
import '../runtime/dart/serve.dart';
import '../runtime/node/config.dart';
import '../runtime/node/serve.dart';

Future<Runtime> serve(
  Server server,
  RuntimeConfig runtime,
) async {
  return switch (runtime) {
    BunRuntimeConfig() => serveBunRuntime(server, runtime),
    DartRuntimeConfig() => serveDartRuntime(server, runtime),
    NodeRuntimeConfig() => serveNodeRuntime(server, runtime),
    _ => throw UnsupportedError(
      'Unsupported RuntimeConfig: ${runtime.runtimeType}. '
      'Add a concrete runtime handler before calling serve().',
    ),
  };
}
