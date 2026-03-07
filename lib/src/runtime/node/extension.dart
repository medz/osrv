import '../../core/extension.dart';
import 'http_host.dart';
import 'interop.dart';

final class NodeRuntimeExtension implements RuntimeExtension {
  const NodeRuntimeExtension({
    this.process,
    this.server,
    this.request,
    this.response,
  });

  final NodeProcess? process;
  final NodeHttpServerHost? server;
  final NodeIncomingMessageHost? request;
  final NodeServerResponseHost? response;

  factory NodeRuntimeExtension.host() {
    return NodeRuntimeExtension(process: nodeProcess);
  }
}
