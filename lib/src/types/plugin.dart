import 'dart:async';

import 'package:ht/ht.dart';

import '../request.dart';
import 'server_handle.dart';

abstract base class ServerPlugin {
  FutureOr<void> onRegister(ServerHandle server) {}

  FutureOr<void> onBeforeServe(ServerHandle server) {}

  FutureOr<void> onAfterServe(ServerHandle server) {}

  FutureOr<void> onBeforeClose(ServerHandle server) {}

  FutureOr<void> onAfterClose(ServerHandle server) {}

  FutureOr<void> onRequest(ServerHandle server, ServerRequest request) {}

  FutureOr<void> onResponse(
    ServerHandle server,
    ServerRequest request,
    Response response,
  ) {}

  FutureOr<void> onError(
    ServerHandle server,
    ServerRequest request,
    Object error,
    StackTrace stackTrace,
  ) {}
}
