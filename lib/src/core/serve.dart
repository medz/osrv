import 'runtime.dart';
import 'runtime_config.dart';
import 'server.dart';
import '../runtime/dart/config.dart';
import '../runtime/dart/serve.dart';

Future<Runtime> serve(
  Server server,
  RuntimeConfig runtime,
) async {
  return switch (runtime) {
    DartRuntimeConfig() => serveDartRuntime(server, runtime),
    _ => throw UnsupportedError(
      'Unsupported RuntimeConfig: ${runtime.runtimeType}. '
      'Add a concrete runtime handler before calling serve().',
    ),
  };
}
