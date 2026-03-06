import 'dart:async';
import 'dart:io';

import '../../core/capabilities.dart';
import '../../core/runtime.dart';

final class DartRuntime implements Runtime {
  DartRuntime({
    required HttpServer server,
    required this.info,
    required this.capabilities,
    required Future<void> closed,
    required this.host,
    required this.port,
    required void Function() onClose,
  }) : _server = server,
       _closed = closed,
       _onClose = onClose;

  final HttpServer _server;
  final Future<void> _closed;
  final void Function() _onClose;
  final String host;
  final int port;
  Future<void>? _closeOperation;

  @override
  final RuntimeInfo info;

  @override
  final RuntimeCapabilities capabilities;

  @override
  Uri get url => Uri(
    scheme: 'http',
    host: host,
    port: port,
  );

  @override
  Future<void> close() => _closeOperation ??= _closeInternal();

  @override
  Future<void> get closed => _closed;

  Future<void> _closeInternal() async {
    _onClose();
    await _server.close();
    await _closed;
  }
}
