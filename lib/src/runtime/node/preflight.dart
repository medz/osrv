// ignore_for_file: public_member_api_docs

import '../../core/capabilities.dart';
import '../../core/errors.dart';
import '../../core/runtime.dart';
import 'config.dart';
import 'extension.dart';
import 'http_host.dart';
import 'probe.dart';

const nodeRuntimePreflightCapabilities = RuntimeCapabilities(
  streaming: true,
  websocket: false,
  fileSystem: true,
  backgroundTask: true,
  rawTcp: true,
  nodeCompat: true,
);

final class NodeRuntimePreflight {
  const NodeRuntimePreflight({
    required this.config,
    required this.info,
    required this.capabilities,
    required this.extension,
    required this.probe,
    required this.httpModule,
    required this.blockReason,
  });

  final NodeRuntimeConfig config;
  final RuntimeInfo info;
  final RuntimeCapabilities capabilities;
  final NodeRuntimeExtension extension;
  final NodeHostProbe probe;
  final NodeHttpModuleHost? httpModule;
  final String? blockReason;

  bool get canServe => blockReason == null;

  bool get isJavaScriptHost => probe.isJavaScriptHost;

  bool get hasNodeProcess => probe.hasNodeProcess;

  bool get isNodeHost => probe.isNodeHost;

  bool get hasHttpModule => httpModule != null;

  String get nodeVersion => probe.nodeVersion ?? 'unknown';

  String get summary {
    if (!isJavaScriptHost) {
      return 'non-js-host';
    }

    if (!hasNodeProcess) {
      return 'js-host-without-node-process';
    }

    if (!hasHttpModule) {
      return 'node-host-without-http-module';
    }

    return 'node-host($nodeVersion)';
  }

  UnsupportedError toUnsupportedError() {
    if (blockReason != null) {
      return UnsupportedError(blockReason!);
    }

    return UnsupportedError(
      'Node runtime host detected ($nodeVersion), but serving could not continue.',
    );
  }
}

NodeRuntimePreflight preflightNodeRuntime(
  NodeRuntimeConfig config, {
  NodeHostProbe? probe,
  NodeHttpModuleHost? httpModule,
}) {
  _validateNodeRuntimeConfig(config);

  final resolvedProbe = probe ?? probeNodeHost();
  final resolvedHttpModule = httpModule ?? nodeHttpModule;
  return NodeRuntimePreflight(
    config: config,
    info: const RuntimeInfo(name: 'node', kind: 'javascript-host'),
    capabilities: nodeRuntimePreflightCapabilities,
    extension: resolvedProbe.extension,
    probe: resolvedProbe,
    httpModule: resolvedHttpModule,
    blockReason: _buildNodeBlockReason(
      probe: resolvedProbe,
      httpModule: resolvedHttpModule,
    ),
  );
}

void _validateNodeRuntimeConfig(NodeRuntimeConfig config) {
  if (config.host.trim().isEmpty) {
    throw RuntimeConfigurationError('NodeRuntimeConfig.host cannot be empty.');
  }

  if (config.port < 0 || config.port > 65535) {
    throw RuntimeConfigurationError(
      'NodeRuntimeConfig.port must be between 0 and 65535.',
    );
  }
}

String? _buildNodeBlockReason({
  required NodeHostProbe probe,
  required NodeHttpModuleHost? httpModule,
}) {
  if (!probe.isJavaScriptHost) {
    return 'Node runtime requires a JavaScript host, but the current host is not JavaScript.';
  }

  if (!probe.hasNodeProcess) {
    return 'Node runtime requires a JavaScript host with Node.js process available. '
        'The current host does not expose Node process bindings.';
  }

  if (httpModule == null) {
    return 'Node runtime requires the node:http host module, but it is not available.';
  }

  return null;
}
