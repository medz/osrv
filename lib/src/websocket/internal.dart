import 'package:ht/ht.dart' as ht;

import '../request.dart';

const String websocketUpgradeHeader = 'x-osrv-upgrade';
const String websocketUpgradeValue = 'websocket';

const String jsRuntimeKey = '__osrv_js_runtime';
const String jsRawRequestKey = '__osrv_js_raw_request';
const String jsRawContextKey = '__osrv_js_raw_context';
const String jsRawServerKey = '__osrv_js_raw_server';
const String jsPendingWebSocketKey = '__osrv_js_pending_websocket';

abstract interface class JsPendingWebSocketUpgrade {
  Future<Object?> accept();
}

bool isWebSocketUpgradeResponse(ht.Response response) {
  if (response.status == 101) {
    return true;
  }

  final upgrade = response.headers.get(websocketUpgradeHeader);
  if (upgrade == null) {
    return false;
  }

  return upgrade.toLowerCase() == websocketUpgradeValue;
}

JsPendingWebSocketUpgrade? takePendingWebSocketUpgrade(ServerRequest request) {
  final pending = request.context.remove(jsPendingWebSocketKey);
  if (pending is JsPendingWebSocketUpgrade) {
    return pending;
  }
  return null;
}
