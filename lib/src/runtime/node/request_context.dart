import 'dart:async';

import '../../core/capabilities.dart';
import '../../core/extension.dart';
import '../../core/request_context.dart';
import '../../core/runtime.dart';
import 'extension.dart';

final class NodeRequestContext implements RequestContext {
  NodeRequestContext({
    required RuntimeInfo runtime,
    required RuntimeCapabilities capabilities,
    required void Function(Future<void> task) onWaitUntil,
    required NodeRuntimeExtension extension,
  }) : _runtime = runtime,
       _capabilities = capabilities,
       _onWaitUntil = onWaitUntil,
       _extension = extension;

  final RuntimeInfo _runtime;
  final RuntimeCapabilities _capabilities;
  final void Function(Future<void> task) _onWaitUntil;
  final NodeRuntimeExtension _extension;

  @override
  RuntimeInfo get runtime => _runtime;

  @override
  RuntimeCapabilities get capabilities => _capabilities;

  @override
  void waitUntil(Future<void> task) => _onWaitUntil(task);

  @override
  T? extension<T extends RuntimeExtension>() {
    if (_extension is T) {
      return _extension as T;
    }

    return null;
  }
}
