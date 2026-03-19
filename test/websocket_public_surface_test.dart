import 'package:osrv/websocket.dart';
import 'package:test/test.dart';

void main() {
  test('package:osrv/websocket.dart exports websocket public types', () {
    WebSocketRequest? request;
    WebSocketHandler? handler;
    WebSocket? socket;
    WebSocketEvent? event;
    WebSocketException? exception;
    WebSocketConnectionClosed? connectionClosed;
    TextDataReceived? text;
    BinaryDataReceived? binary;
    CloseReceived? close;

    expect(request, isNull);
    expect(handler, isNull);
    expect(socket, isNull);
    expect(event, isNull);
    expect(exception, isNull);
    expect(connectionClosed, isNull);
    expect(text, isNull);
    expect(binary, isNull);
    expect(close, isNull);
  });
}
