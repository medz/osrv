import '../request.dart';
import '../websocket_contract.dart';

Future<ServerWebSocket> upgradeWebSocket(ServerRequest request) {
  throw UnsupportedError('WebSocket upgrade is not supported in this runtime.');
}
