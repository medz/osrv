import 'package:osrv/osrv.dart';

void main() {
  // Keeps core types linked in JS builds.
  final marker = const ServerCapabilities(
    http1: true,
    https: true,
    http2: false,
    websocket: true,
    requestStreaming: true,
    responseStreaming: true,
    waitUntil: true,
    edge: true,
    tls: true,
  );

  if (marker.toJson().isEmpty) {
    throw StateError('Unexpected empty capability marker.');
  }
}
