import '../../core/extension.dart';

import 'host.dart';

final class CloudflareRuntimeExtension<
    Env extends Object?,
    Request extends Object?> implements RuntimeExtension {
  const CloudflareRuntimeExtension({
    this.env,
    this.context,
    this.request,
  });

  final Env? env;
  final CloudflareExecutionContext? context;
  final Request? request;
}
