import 'dart:async';

import 'capabilities.dart';
import 'extension.dart';
import 'runtime.dart';

base class ServerLifecycleContext {
  ServerLifecycleContext({
    required this.runtime,
    required this.capabilities,
    RuntimeExtension? extension,
  }) : _extension = extension;

  final RuntimeInfo runtime;
  final RuntimeCapabilities capabilities;
  final RuntimeExtension? _extension;

  T? extension<T extends RuntimeExtension>() {
    final extension = _extension;
    if (extension is T) {
      return extension;
    }

    return null;
  }
}

base class RequestContext extends ServerLifecycleContext {
  RequestContext({
    required super.runtime,
    required super.capabilities,
    required void Function(Future<void> task) onWaitUntil,
    super.extension,
  }) : _onWaitUntil = onWaitUntil;

  final void Function(Future<void> task) _onWaitUntil;

  void waitUntil(Future<void> task) {
    _onWaitUntil(task);
  }
}
