// ignore_for_file: public_member_api_docs

final class NodeHostObject {
  const NodeHostObject();
}

final class NodeProcess {
  const NodeProcess({
    this.version = '',
    this.versions = const NodeProcessVersions(),
    this.env = const NodeProcessEnv(),
  });

  final String version;
  final NodeProcessVersions versions;
  final NodeProcessEnv env;
}

final class NodeProcessVersions {
  const NodeProcessVersions({this.node});

  final String? node;
}

final class NodeProcessEnv {
  const NodeProcessEnv();
}

final class NodeServerHost {
  const NodeServerHost();
}

final class NodeRequestHost {
  const NodeRequestHost();
}

final class NodeResponseHost {
  const NodeResponseHost();
}

NodeHostObject? get globalThis => null;

NodeProcess? get nodeProcess => null;

String? nodeProcessVersion(NodeProcess process) {
  return process.versions.node ?? process.version;
}
