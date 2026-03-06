import '../../core/capabilities.dart';
import '../../core/errors.dart';
import '../../core/runtime.dart';
import 'config.dart';
import 'extension.dart';
import 'probe.dart';

const bunRuntimePreflightCapabilities = RuntimeCapabilities(
  streaming: true,
  websocket: false,
  fileSystem: true,
  backgroundTask: true,
  rawTcp: false,
  nodeCompat: true,
);

final class BunRuntimePreflight {
  const BunRuntimePreflight({
    required this.config,
    required this.info,
    required this.capabilities,
    required this.extension,
    required this.probe,
    required this.blockReason,
  });

  final BunRuntimeConfig config;
  final RuntimeInfo info;
  final RuntimeCapabilities capabilities;
  final BunRuntimeExtension extension;
  final BunHostProbe probe;
  final String? blockReason;

  bool get canServe => blockReason == null;

  bool get isJavaScriptHost => probe.isJavaScriptHost;

  bool get hasBunGlobal => probe.hasBunGlobal;

  bool get hasServe => probe.hasServe;

  bool get isBunHost => probe.isBunHost;

  String get bunVersion => probe.version ?? 'unknown';

  String get summary {
    if (!isJavaScriptHost) {
      return 'non-js-host';
    }

    if (!hasBunGlobal) {
      return 'js-host-without-bun-global';
    }

    if (!hasServe) {
      return 'bun-host-without-serve';
    }

    return 'bun-host-not-implemented($bunVersion)';
  }

  UnsupportedError toUnsupportedError() {
    if (blockReason != null) {
      return UnsupportedError(blockReason!);
    }

    return UnsupportedError(
      'Bun runtime host detected ($bunVersion), but serving could not continue.',
    );
  }
}

BunRuntimePreflight preflightBunRuntime(
  BunRuntimeConfig config, {
  BunHostProbe? probe,
}) {
  _validateBunRuntimeConfig(config);

  final resolvedProbe = probe ?? probeBunHost();
  return BunRuntimePreflight(
    config: config,
    info: const RuntimeInfo(
      name: 'bun',
      kind: 'javascript-host',
    ),
    capabilities: bunRuntimePreflightCapabilities,
    extension: resolvedProbe.extension,
    probe: resolvedProbe,
    blockReason: _buildBunBlockReason(resolvedProbe),
  );
}

void _validateBunRuntimeConfig(BunRuntimeConfig config) {
  if (config.host.trim().isEmpty) {
    throw RuntimeConfigurationError(
      'BunRuntimeConfig.host cannot be empty.',
    );
  }

  if (config.port < 0 || config.port > 65535) {
    throw RuntimeConfigurationError(
      'BunRuntimeConfig.port must be between 0 and 65535.',
    );
  }
}

String? _buildBunBlockReason(BunHostProbe probe) {
  if (!probe.isJavaScriptHost) {
    return 'Bun runtime requires a JavaScript host, but the current host is not JavaScript.';
  }

  if (!probe.hasBunGlobal) {
    return 'Bun runtime requires the Bun global object, but it is not available on the current host.';
  }

  if (!probe.hasServe) {
    return 'Bun runtime requires Bun.serve, but it is not available on the current host.';
  }

  return 'Bun runtime host detected (${probe.version ?? 'unknown'}), but serving is not implemented yet.';
}
