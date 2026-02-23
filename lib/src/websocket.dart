import 'request.dart';
import 'websocket/websocket_stub.dart'
    if (dart.library.io) 'websocket/websocket_io.dart'
    if (dart.library.js_interop) 'websocket/websocket_js.dart'
    as impl;
import 'websocket_contract.dart';

Future<ServerWebSocket> upgradeWebSocket(ServerRequest request) {
  return impl.upgradeWebSocket(request);
}
