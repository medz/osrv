import 'dart:async';

import '../../../core/capabilities.dart';
import '../../../core/runtime.dart';

base class ServerRuntimeHandle implements Runtime {
  ServerRuntimeHandle({
    required this.info,
    required this.capabilities,
    required Future<void> closed,
    required Uri? url,
    required Future<void> Function() onClose,
  }) : _closed = closed,
       _url = url,
       _onClose = onClose;

  final Future<void> _closed;
  final Uri? _url;
  final Future<void> Function() _onClose;
  Future<void>? _closeOperation;

  @override
  final RuntimeInfo info;

  @override
  final RuntimeCapabilities capabilities;

  @override
  Uri? get url => _url;

  @override
  Future<void> close() => _closeOperation ??= _onClose();

  @override
  Future<void> get closed => _closed;
}
