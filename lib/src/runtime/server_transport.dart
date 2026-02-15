import 'package:ht/ht.dart' show Response;

import '../request.dart';
import '../types.dart';
import 'server_transport_stub.dart'
    if (dart.library.js_interop) 'server_transport_js.dart'
    if (dart.library.io) 'server_transport_io.dart'
    as impl;

abstract interface class ServerTransportHost {
  int get resolvedPort;
  String get resolvedHostname;
  ServerProtocol get resolvedProtocol;
  bool get reusePort;
  bool get trustProxy;
  bool get silent;
  bool get isProduction;
  TlsOptions? get tlsOptions;
  GracefulShutdownOptions get gracefulShutdown;
  ServerSecurityLimits get securityLimits;
  WebSocketLimits get webSocketLimits;

  Future<Response> dispatch(ServerRequest request);
  void trackBackgroundTask(Future<Object?> task);
  void logInfo(String message);
  void logWarn(String message);
  void logError(String message, [Object? error, StackTrace? stackTrace]);
}

abstract interface class ServerTransport {
  String get runtimeName;
  ServerCapabilities get capabilities;
  String? get url;

  Future<void> serve();
  Future<void> close({required bool force});
}

ServerTransport createServerTransport(ServerTransportHost host) {
  return impl.createServerTransport(host);
}
