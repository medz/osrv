// ignore_for_file: public_member_api_docs

import 'extension.dart';
import 'interop.dart';

final class DenoHostProbe {
  const DenoHostProbe({
    required this.isJavaScriptHost,
    required this.hasDenoGlobal,
    required this.hasServe,
    required this.version,
    required this.extension,
  });

  final bool isJavaScriptHost;
  final bool hasDenoGlobal;
  final bool hasServe;
  final String? version;
  final DenoRuntimeExtension extension;

  bool get isDenoHost => hasDenoGlobal;
}

DenoHostProbe probeDenoHost() {
  final deno = denoGlobal;
  return DenoHostProbe(
    isJavaScriptHost: globalThis != null,
    hasDenoGlobal: deno != null,
    hasServe: deno != null && denoHasServe(deno),
    version: deno == null ? null : denoRuntimeVersion(deno),
    extension: DenoRuntimeExtension(deno: deno),
  );
}
