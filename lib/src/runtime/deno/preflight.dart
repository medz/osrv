// ignore_for_file: public_member_api_docs

import '../../core/capabilities.dart';
import '../../core/errors.dart';
import '../../core/runtime.dart';
import 'extension.dart';
import 'probe.dart';

const denoRuntimePreflightCapabilities = RuntimeCapabilities(
  streaming: true,
  websocket: false,
  fileSystem: true,
  backgroundTask: true,
  rawTcp: true,
  nodeCompat: true,
);

final class DenoRuntimePreflight {
  const DenoRuntimePreflight({
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
  final DenoRuntimeExtension extension;
  final DenoHostProbe probe;
  final String? blockReason;

  bool get canServe => blockReason == null;

  bool get isJavaScriptHost => probe.isJavaScriptHost;

  bool get hasDenoGlobal => probe.hasDenoGlobal;

  bool get hasServe => probe.hasServe;

  bool get isDenoHost => probe.isDenoHost;

  String get denoVersion => probe.version ?? 'unknown';

  String get summary {
    if (!isJavaScriptHost) {
      return 'non-js-host';
    }

    if (!hasDenoGlobal) {
      return 'js-host-without-deno-global';
    }

    if (!hasServe) {
      return 'deno-host-without-serve';
    }

    return 'deno-host($denoVersion)';
  }

  UnsupportedError toUnsupportedError() {
    if (blockReason != null) {
      return UnsupportedError(blockReason!);
    }

    return UnsupportedError(
      'Deno runtime host detected ($denoVersion), but serving could not continue.',
    );
  }
}

DenoRuntimePreflight preflightDenoRuntime({
  String host = '127.0.0.1',
  int port = 3000,
  DenoHostProbe? probe,
}) {
  final normalizedHost = host.trim();
  _validateDenoServeParameters(host: normalizedHost, port: port);

  final resolvedProbe = probe ?? probeDenoHost();
  return DenoRuntimePreflight(
    host: normalizedHost,
    port: port,
    info: const RuntimeInfo(name: 'deno', kind: 'javascript-host'),
    capabilities: denoRuntimePreflightCapabilities,
    extension: resolvedProbe.extension,
    probe: resolvedProbe,
    blockReason: _buildDenoBlockReason(resolvedProbe),
  );
}

void _validateDenoServeParameters({required String host, required int port}) {
  if (host.isEmpty) {
    throw RuntimeConfigurationError('Deno runtime host cannot be empty.');
  }

  if (port < 0 || port > 65535) {
    throw RuntimeConfigurationError(
      'Deno runtime port must be between 0 and 65535.',
    );
  }
}

String? _buildDenoBlockReason(DenoHostProbe probe) {
  if (!probe.isJavaScriptHost) {
    return 'Deno runtime requires a JavaScript host, but the current host is not JavaScript.';
  }

  if (!probe.hasDenoGlobal) {
    return 'Deno runtime requires the Deno global object, but it is not available on the current host.';
  }

  if (!probe.hasServe) {
    return 'Deno runtime requires Deno.serve, but it is not available on the current host.';
  }

  return null;
}
