// ignore_for_file: public_member_api_docs

@JS()
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

@JS('globalThis')
external JSObject get _globalThis;

@JS('Bun')
external JSObject? get _bunGlobal;

extension type BunHostObject._(JSObject _) implements JSObject {}

extension type BunGlobal._(JSObject _) implements JSObject {
  external JSString? get version;
  @JS('serve')
  external JSFunction? get serve;
}

extension type BunServerHost._(JSObject _) implements JSObject {
  external JSNumber? get port;
  external JSFunction get stop;
}

extension type BunServerWebSocketHost._(JSObject _) implements JSObject {}

BunHostObject? get globalThis => BunHostObject._(_globalThis);

BunGlobal? get bunGlobal {
  final value = _bunGlobal;
  if (value == null) {
    return null;
  }

  return BunGlobal._(value);
}

String? bunVersion(BunGlobal bun) => bun.version?.toDart;

bool bunHasServe(BunGlobal bun) => bun.serve != null;

BunServerHost bunServe(
  BunGlobal bun, {
  required String host,
  required int port,
  required Object fetch,
  Object? websocket,
}) {
  final options = JSObject()
    ..setProperty('port'.toJS, port.toJS)
    ..setProperty('hostname'.toJS, host.toJS)
    ..setProperty('fetch'.toJS, fetch as JSAny);
  if (websocket != null) {
    options.setProperty('websocket'.toJS, websocket as JSAny);
  }

  final server = bun.callMethodVarArgs<JSObject>('serve'.toJS, [options]);
  return BunServerHost._(server);
}

int? bunServerPort(BunServerHost server) => server.port?.toDartInt;

Future<void> stopBunServer(BunServerHost server, {bool force = false}) async {
  final result = server.stop.callAsFunction(server, force.toJS);
  if (result != null) {
    await (result as JSPromise<JSAny?>).toDart;
  }
}

bool bunServerUpgrade(
  BunServerHost server,
  web.Request request, {
  int? token,
  String? protocol,
}) {
  final options = JSObject();

  if (token != null) {
    options.setProperty('data'.toJS, token.toJS);
  }

  if (protocol != null) {
    final headers = JSObject()
      ..setProperty('Sec-WebSocket-Protocol'.toJS, protocol.toJS);
    options.setProperty('headers'.toJS, headers);
  }

  final result = server.callMethodVarArgs<JSBoolean>('upgrade'.toJS, [
    request,
    options,
  ]);
  return result.toDart;
}

JSObject bunWebSocketHandlers({
  required JSExportedDartFunction open,
  required JSExportedDartFunction message,
  required JSExportedDartFunction close,
  required JSExportedDartFunction error,
  required JSExportedDartFunction drain,
}) {
  return JSObject()
    ..setProperty('open'.toJS, open)
    ..setProperty('message'.toJS, message)
    ..setProperty('close'.toJS, close)
    ..setProperty('error'.toJS, error)
    ..setProperty('drain'.toJS, drain);
}

int? bunServerWebSocketToken(BunServerWebSocketHost socket) {
  final data = socket.getProperty<JSAny?>('data'.toJS);
  final value = data?.dartify();
  return switch (value) {
    int() => value,
    num() => value.toInt(),
    _ => null,
  };
}

void bunServerWebSocketSendText(BunServerWebSocketHost socket, String message) {
  socket.callMethodVarArgs<JSAny?>('send'.toJS, [message.toJS]);
}

void bunServerWebSocketSendBytes(
  BunServerWebSocketHost socket,
  Uint8List bytes,
) {
  socket.callMethodVarArgs<JSAny?>('send'.toJS, [bytes.toJS]);
}

void bunServerWebSocketClose(
  BunServerWebSocketHost socket, {
  int? code,
  String? reason,
}) {
  final arguments = <JSAny?>[];
  if (code != null) {
    arguments.add(code.toJS);
    if (reason != null) {
      arguments.add(reason.toJS);
    }
  }

  socket.callMethodVarArgs<JSAny?>('close'.toJS, arguments);
}
