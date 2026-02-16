import 'package:ht/ht.dart' as ht;

import 'types.dart';

const Object serverRequestNoBody = Object();

/// Public request interface used by osrv handlers.
abstract interface class ServerRequest implements ht.Request {
  /// Mutable per-request state bag for middleware/handlers.
  Map<String, Object?> get context;

  /// Runtime metadata for the current request.
  RequestRuntimeContext? get runtime;

  /// Resolved client IP when available.
  String? get ip;

  /// Runtime wait-until hook when available.
  WaitUntil? get waitUntil;

  @override
  ServerRequest clone();

  @override
  ServerRequest copyWith({
    Uri? url,
    String? method,
    ht.Headers? headers,
    Object? body = serverRequestNoBody,
  });
}
