import 'request.dart';
import 'types.dart';
import 'websocket/websocket_stub.dart'
    if (dart.library.io) 'websocket/websocket_io.dart'
    as impl;
import 'websocket_contract.dart';

Future<ServerWebSocket> upgradeWebSocket(
  ServerRequest request, {
  WebSocketLimits limits = const WebSocketLimits(),
}) {
  return impl.upgradeWebSocket(request, limits: limits);
}
