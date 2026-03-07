import '../../core/extension.dart';
import 'request_host.dart';

import 'interop.dart';

/// Exposes Bun-specific host objects through [RequestContext.extension].
final class BunRuntimeExtension implements RuntimeExtension {
  /// Creates a Bun runtime extension snapshot.
  const BunRuntimeExtension({this.bun, this.server, this.request});

  /// The Bun global object when running on a Bun host.
  final BunGlobal? bun;

  /// The Bun server created by `Bun.serve`, when one exists.
  final BunServerHost? server;

  /// The Bun-native request object for the active request, when one exists.
  final BunRequestHost? request;

  /// Creates a host-level extension before the server starts handling requests.
  factory BunRuntimeExtension.host() {
    return BunRuntimeExtension(bun: bunGlobal);
  }
}
