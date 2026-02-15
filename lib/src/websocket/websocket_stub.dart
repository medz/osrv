import '../request.dart';
import '../types.dart';
import '../websocket_contract.dart';

Future<ServerWebSocket> upgradeWebSocket(
  ServerRequest request, {
  WebSocketLimits limits = const WebSocketLimits(),
}) {
  throw UnsupportedError(
    'WebSocket upgrade is not supported in this runtime. '
    'Use dart:io runtime transport or generated runtime adapter.',
  );
}
