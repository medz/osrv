import '../../core/extension.dart';
import 'http_host.dart';
import 'interop.dart';

/// Exposes Node-specific host objects through [RequestContext.extension].
final class NodeRuntimeExtension implements RuntimeExtension {
  /// Creates a Node runtime extension snapshot.
  const NodeRuntimeExtension({
    this.process,
    this.server,
    this.request,
    this.response,
  });

  /// The Node `process` object when running on a Node host.
  final NodeProcess? process;

  /// The active Node HTTP server, when the runtime is serving requests.
  final NodeHttpServerHost? server;

  /// The raw incoming Node request for the active request, when one exists.
  final NodeIncomingMessageHost? request;

  /// The raw Node response writer for the active request, when one exists.
  final NodeServerResponseHost? response;

  /// Creates a host-level extension before the server starts handling requests.
  factory NodeRuntimeExtension.host() {
    return NodeRuntimeExtension(process: nodeProcess);
  }
}
