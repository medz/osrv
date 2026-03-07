import 'extension.dart';
import 'interop.dart';

final class NodeHostProbe {
  const NodeHostProbe({
    required this.isJavaScriptHost,
    required this.hasNodeProcess,
    required this.nodeVersion,
    required this.extension,
  });

  final bool isJavaScriptHost;
  final bool hasNodeProcess;
  final String? nodeVersion;
  final NodeRuntimeExtension extension;

  bool get isNodeHost => hasNodeProcess;
}

NodeHostProbe probeNodeHost() {
  final process = nodeProcess;
  return NodeHostProbe(
    isJavaScriptHost: globalThis != null,
    hasNodeProcess: process != null,
    nodeVersion: process == null ? null : nodeProcessVersion(process),
    extension: NodeRuntimeExtension(process: process),
  );
}
