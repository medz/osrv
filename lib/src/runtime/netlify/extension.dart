import '../../core/extension.dart';

import 'host.dart';

/// Exposes Netlify Functions host values through [RequestContext.extension].
final class NetlifyRuntimeExtension<Request extends Object?>
    implements RuntimeExtension {
  /// Creates a Netlify runtime extension snapshot.
  const NetlifyRuntimeExtension({this.context, this.request});

  /// Netlify's function context for the current invocation.
  final NetlifyContext? context;

  /// The host-native request value for the current invocation.
  final Request? request;
}
