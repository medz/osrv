import '../../core/extension.dart';

import 'interop.dart';

final class BunRuntimeExtension implements RuntimeExtension {
  const BunRuntimeExtension({
    this.bun,
  });

  final BunGlobal? bun;

  factory BunRuntimeExtension.host() {
    return BunRuntimeExtension(bun: bunGlobal);
  }
}
