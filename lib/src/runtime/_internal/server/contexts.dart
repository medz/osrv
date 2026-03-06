import 'dart:async';

import '../../../core/capabilities.dart';
import '../../../core/extension.dart';
import '../../../core/request_context.dart';
import '../../../core/runtime.dart';
import '../../../core/server.dart';

typedef ServerRuntimeWaitUntil<T extends RuntimeExtension> = void Function(
  T extension,
  Future<void> task,
);

class ServerLifecycleContextImpl<T extends RuntimeExtension>
    implements ServerLifecycleContext {
  ServerLifecycleContextImpl({
    required RuntimeInfo runtime,
    required RuntimeCapabilities capabilities,
    required T extension,
  }) : _runtime = runtime,
       _capabilities = capabilities,
       _extension = extension;

  final RuntimeInfo _runtime;
  final RuntimeCapabilities _capabilities;
  final T _extension;

  @override
  RuntimeInfo get runtime => _runtime;

  @override
  RuntimeCapabilities get capabilities => _capabilities;

  @override
  X? extension<X extends RuntimeExtension>() {
    if (_extension is X) {
      return _extension as X;
    }

    return null;
  }
}

class ServerRequestContextImpl<T extends RuntimeExtension>
    implements RequestContext {
  ServerRequestContextImpl({
    required RuntimeInfo runtime,
    required RuntimeCapabilities capabilities,
    required T extension,
    required ServerRuntimeWaitUntil<T> onWaitUntil,
  }) : _runtime = runtime,
       _capabilities = capabilities,
       _extension = extension,
       _onWaitUntil = onWaitUntil;

  final RuntimeInfo _runtime;
  final RuntimeCapabilities _capabilities;
  final T _extension;
  final ServerRuntimeWaitUntil<T> _onWaitUntil;

  @override
  RuntimeInfo get runtime => _runtime;

  @override
  RuntimeCapabilities get capabilities => _capabilities;

  @override
  void waitUntil(Future<void> task) {
    _onWaitUntil(_extension, task);
  }

  @override
  X? extension<X extends RuntimeExtension>() {
    if (_extension is X) {
      return _extension as X;
    }

    return null;
  }
}
