// ignore_for_file: public_member_api_docs

import '../../core/capabilities.dart';
import '../../core/errors.dart';
import '../../core/runtime.dart';
import 'extension.dart';
import 'probe.dart';

const bunRuntimePreflightCapabilities = RuntimeCapabilities(
  streaming: true,
  websocket: true,
  fileSystem: true,
  backgroundTask: true,
  rawTcp: false,
  nodeCompat: true,
);

final class BunRuntimePreflight {
  const BunRuntimePreflight({
    required this.host,
    required this.port,
    required this.info,
    required this.capabilities,
    required this.extension,
    required this.probe,
    required this.blockReason,
  });

  final String host;
  final int port;
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

    return 'bun-host($bunVersion)';
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

BunRuntimePreflight preflightBunRuntime({
  String host = '127.0.0.1',
  int port = 3000,
  BunHostProbe? probe,
}) {
  final normalizedHost = host.trim();
  _validateBunServeParameters(host: normalizedHost, port: port);

  final resolvedProbe = probe ?? probeBunHost();
  return BunRuntimePreflight(
    host: normalizedHost,
    port: port,
    info: const RuntimeInfo(name: 'bun', kind: 'javascript-host'),
    capabilities: bunRuntimePreflightCapabilities,
    extension: resolvedProbe.extension,
    probe: resolvedProbe,
    blockReason: _buildBunBlockReason(resolvedProbe),
  );
}

void _validateBunServeParameters({required String host, required int port}) {
  if (host.trim().isEmpty) {
    throw RuntimeConfigurationError('Bun runtime host cannot be empty.');
  }

  if (port < 0 || port > 65535) {
    throw RuntimeConfigurationError(
      'Bun runtime port must be between 0 and 65535.',
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

  return null;
}
