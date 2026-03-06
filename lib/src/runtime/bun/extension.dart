import '../../core/extension.dart';
import 'request_host.dart';

import 'interop.dart';

final class BunRuntimeExtension implements RuntimeExtension {
  const BunRuntimeExtension({this.bun, this.server, this.request});

  final BunGlobal? bun;
  final BunServerHost? server;
  final BunRequestHost? request;

  factory BunRuntimeExtension.host() {
    return BunRuntimeExtension(bun: bunGlobal);
  }
}
