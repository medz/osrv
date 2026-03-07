import '../../core/extension.dart';

import 'host.dart';

/// Exposes Cloudflare Worker host values through [RequestContext.extension].
final class CloudflareRuntimeExtension<
  Env extends Object?,
  Request extends Object?
>
    implements RuntimeExtension {
  /// Creates a Cloudflare runtime extension snapshot.
  const CloudflareRuntimeExtension({this.env, this.context, this.request});

  /// Cloudflare environment bindings for the current worker invocation.
  final Env? env;

  /// Cloudflare's execution context for the current worker invocation.
  final CloudflareExecutionContext? context;

  /// The host-native request value for the current invocation.
  final Request? request;
}
