import '../../core/extension.dart';

import 'host.dart';

final class CloudflareRuntimeExtension implements RuntimeExtension {
  const CloudflareRuntimeExtension({
    this.env,
    this.context,
    this.request,
  });

  final Object? env;
  final CloudflareExecutionContext? context;
  final Object? request;
}
