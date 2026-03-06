import '../../core/capabilities.dart';
import '../../core/extension.dart';
import '../../core/request_context.dart';
import '../../core/runtime.dart';
import 'extension.dart';
import 'host.dart';

final class VercelRequestContext implements RequestContext {
  VercelRequestContext({
    required RuntimeInfo runtime,
    required RuntimeCapabilities capabilities,
    required VercelRuntimeExtension<Object?, Object?> extension,
  }) : _runtime = runtime,
       _capabilities = capabilities,
       _extension = extension;

  final RuntimeInfo _runtime;
  final RuntimeCapabilities _capabilities;
  final VercelRuntimeExtension<Object?, Object?> _extension;

  @override
  RuntimeInfo get runtime => _runtime;

  @override
  RuntimeCapabilities get capabilities => _capabilities;

  @override
  void waitUntil(Future<void> task) {
    vercelWaitUntil(
      _extension.helpers is VercelFunctionHelpersHost
          ? _extension.helpers as VercelFunctionHelpersHost
          : null,
      task,
    );
  }

  @override
  T? extension<T extends RuntimeExtension>() {
    if (_extension is T) {
      return _extension as T;
    }

    return null;
  }
}
