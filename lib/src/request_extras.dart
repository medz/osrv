import 'package:ht/ht.dart';

import 'types.dart';

final Expando<_RequestExtras> _requestExtras = Expando<_RequestExtras>('osrv');

_RequestExtras _extrasFor(Request request) {
  return _requestExtras[request] ??= _RequestExtras();
}

void attachRequestRuntime(
  Request request, {
  RequestRuntimeContext? runtime,
  Map<String, Object?>? context,
  String? ip,
  WaitUntil? waitUntil,
}) {
  final extras = _extrasFor(request);
  extras.runtime = runtime;
  extras.context = context;
  extras.ip = ip;
  extras.waitUntil = waitUntil;
}

extension ServerRequestX on Request {
  RequestRuntimeContext? get runtime => _extrasFor(this).runtime;

  set runtime(RequestRuntimeContext? value) {
    _extrasFor(this).runtime = value;
  }

  Map<String, Object?> get context {
    final extras = _extrasFor(this);
    return extras.context ??= <String, Object?>{};
  }

  set context(Map<String, Object?> value) {
    _extrasFor(this).context = value;
  }

  String? get ip => _extrasFor(this).ip;

  set ip(String? value) {
    _extrasFor(this).ip = value;
  }

  WaitUntil? get waitUntil => _extrasFor(this).waitUntil;

  set waitUntil(WaitUntil? value) {
    _extrasFor(this).waitUntil = value;
  }
}

void markWebSocketUpgraded(Request request) {
  _extrasFor(request).webSocketUpgraded = true;
}

bool isWebSocketUpgraded(Request request) {
  return _extrasFor(request).webSocketUpgraded;
}

void setRawWebSocket(Request request, Object socket) {
  _extrasFor(request).rawWebSocket = socket;
}

Object? takeRawWebSocket(Request request) {
  final extras = _extrasFor(request);
  final socket = extras.rawWebSocket;
  extras.rawWebSocket = null;
  return socket;
}

final class _RequestExtras {
  RequestRuntimeContext? runtime;
  Map<String, Object?>? context;
  String? ip;
  WaitUntil? waitUntil;
  bool webSocketUpgraded = false;
  Object? rawWebSocket;
}
