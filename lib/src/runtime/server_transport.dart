import 'package:ht/ht.dart';

import '../core/config.dart';
import '../request.dart';
import '../types/runtime.dart';
import 'server_transport_stub.dart'
    if (dart.library.io) 'server_transport_io.dart'
    if (dart.library.js_interop) 'server_transport_js.dart'
    as runtime_impl;

typedef DispatchRequest = Future<Response> Function(ServerRequest request);
typedef TrackBackgroundTask = void Function(Future<Object?> task);

abstract interface class ServerTransport {
  Runtime get runtime;
  String get hostname;
  int get port;
  Uri get url;
  String get addr;

  Future<void> serve();
  Future<void> ready();
  Future<void> close({required bool force});
}

ServerTransport createServerTransport({
  required ServerConfig config,
  required DispatchRequest dispatch,
  required TrackBackgroundTask trackBackgroundTask,
}) {
  return runtime_impl.createServerTransport(
    config: config,
    dispatch: dispatch,
    trackBackgroundTask: trackBackgroundTask,
  );
}
