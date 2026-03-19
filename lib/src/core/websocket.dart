import 'dart:async';

import 'package:ht/ht.dart' show Response;
import 'package:web_socket/web_socket.dart' as ws;

/// Handles an accepted websocket session after the host upgrade completes.
typedef WebSocketHandler = FutureOr<void> Function(ws.WebSocket socket);

/// Request-scoped websocket upgrade capability exposed by a runtime.
abstract interface class WebSocketRequest {
  /// Whether the active request is a websocket upgrade attempt.
  bool get isUpgradeRequest;

  /// The subprotocols requested by the client handshake.
  List<String> get requestedProtocols;

  /// Returns a response-compatible upgrade outcome for `Server.fetch(...)`.
  Response accept(WebSocketHandler handler, {String? protocol});
}
