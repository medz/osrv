import '../../core/extension.dart';
import 'interop.dart';
import 'request_host.dart';

/// Exposes Deno-specific host objects through [RequestContext.extension].
final class DenoRuntimeExtension implements RuntimeExtension {
  /// Creates a Deno runtime extension snapshot.
  const DenoRuntimeExtension({this.deno, this.server, this.request});

  /// The Deno global object when running on a Deno host.
  final DenoGlobal? deno;

  /// The active Deno HTTP server, when the runtime is serving requests.
  final DenoHttpServerHost? server;

  /// The raw Deno request for the active request, when one exists.
  final DenoRequestHost? request;

  /// Creates a host-level extension before the server starts handling requests.
  factory DenoRuntimeExtension.host() {
    return DenoRuntimeExtension(deno: denoGlobal);
  }
}
