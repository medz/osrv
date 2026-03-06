import '../../core/capabilities.dart';
import '../../core/extension.dart';
import '../../core/runtime.dart';
import '../../core/server.dart';
import 'extension.dart';

final class CloudflareServerLifecycleContext implements ServerLifecycleContext {
  CloudflareServerLifecycleContext({
    required RuntimeInfo runtime,
    required RuntimeCapabilities capabilities,
    required CloudflareRuntimeExtension<Object?, Object?> extension,
  }) : _runtime = runtime,
       _capabilities = capabilities,
       _extension = extension;

  final RuntimeInfo _runtime;
  final RuntimeCapabilities _capabilities;
  final CloudflareRuntimeExtension<Object?, Object?> _extension;

  @override
  RuntimeInfo get runtime => _runtime;

  @override
  RuntimeCapabilities get capabilities => _capabilities;

  @override
  T? extension<T extends RuntimeExtension>() {
    if (_extension is T) {
      return _extension as T;
    }

    return null;
  }
}
