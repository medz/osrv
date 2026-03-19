// ignore_for_file: public_member_api_docs

@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Cloudflare Worker execution context for a single fetch event.
extension type CloudflareExecutionContext._(JSObject _) implements JSObject {
  /// Registers background work with the worker host.
  external void waitUntil(JSPromise task);

  /// Lets the worker continue through the platform exception pipeline.
  external void passThroughOnException();
}

@JS('Response')
external JSFunction? get _responseConstructor;

@JS('WebSocketPair')
extension type CloudflareWebSocketPairHost._(JSObject _) implements JSObject {
  external factory CloudflareWebSocketPairHost();

  @JS('0')
  external CloudflareWebSocketHost get client;

  @JS('1')
  external CloudflareWebSocketHost get server;
}

extension type CloudflareWebSocketHost._(JSObject _) implements JSObject {}

/// Runs [task] with Cloudflare's background execution contract when available.
void cloudflareWaitUntil(
  CloudflareExecutionContext? context,
  Future<void> task,
) {
  if (context == null) {
    unawaited(
      task.catchError((Object error, StackTrace stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
      }),
    );
    return;
  }

  context.waitUntil(task.toJS);
}

CloudflareWebSocketPairHost? cloudflareCreateWebSocketPair() {
  try {
    return CloudflareWebSocketPairHost();
  } catch (_) {
    return null;
  }
}

void cloudflareWebSocketAccept(CloudflareWebSocketHost socket) {
  socket.callMethodVarArgs<JSAny?>('accept'.toJS);
}

void cloudflareWebSocketAddEventListener(
  CloudflareWebSocketHost socket,
  String type,
  JSFunction listener,
) {
  socket.callMethodVarArgs<JSAny?>('addEventListener'.toJS, [
    type.toJS,
    listener,
  ]);
}

void cloudflareWebSocketSendText(
  CloudflareWebSocketHost socket,
  String message,
) {
  socket.callMethodVarArgs<JSAny?>('send'.toJS, [message.toJS]);
}

void cloudflareWebSocketSendBytes(
  CloudflareWebSocketHost socket,
  Uint8List bytes,
) {
  socket.callMethodVarArgs<JSAny?>('send'.toJS, [bytes.toJS]);
}

void cloudflareWebSocketClose(
  CloudflareWebSocketHost socket, {
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

String cloudflareWebSocketProtocol(CloudflareWebSocketHost socket) {
  return socket.getProperty<JSString?>('protocol'.toJS)?.toDart ?? '';
}

web.Response cloudflareUpgradeResponse(
  CloudflareWebSocketHost socket, {
  String? protocol,
}) {
  final init = web.ResponseInit(
    status: 101,
    statusText: 'Switching Protocols',
    headers: _upgradeHeaders(protocol: protocol),
  );
  final object = init as JSObject;
  object.setProperty('webSocket'.toJS, socket);

  final constructor = _responseConstructor;
  if (constructor == null) {
    throw UnsupportedError('Cloudflare websocket upgrade requires Response.');
  }

  return constructor.callAsConstructorVarArgs<web.Response>([null, object]);
}

web.Headers _upgradeHeaders({String? protocol}) {
  final headers = web.Headers();
  headers.append('upgrade', 'websocket');
  headers.append('connection', 'Upgrade');
  if (protocol != null && protocol.isNotEmpty) {
    headers.append('sec-websocket-protocol', protocol);
  }
  return headers;
}
