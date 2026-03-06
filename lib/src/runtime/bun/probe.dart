import 'extension.dart';
import 'interop.dart';

final class BunHostProbe {
  const BunHostProbe({
    required this.isJavaScriptHost,
    required this.hasBunGlobal,
    required this.hasServe,
    required this.version,
    required this.extension,
  });

  final bool isJavaScriptHost;
  final bool hasBunGlobal;
  final bool hasServe;
  final String? version;
  final BunRuntimeExtension extension;

  bool get isBunHost => hasBunGlobal;
}

BunHostProbe probeBunHost() {
  final bun = bunGlobal;
  return BunHostProbe(
    isJavaScriptHost: globalThis != null,
    hasBunGlobal: bun != null,
    hasServe: bun != null && bunHasServe(bun),
    version: bun == null ? null : bunVersion(bun),
    extension: BunRuntimeExtension(
      bun: bun,
    ),
  );
}
