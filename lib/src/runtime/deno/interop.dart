// ignore_for_file: public_member_api_docs

@JS()
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('globalThis')
external JSObject get _globalThis;

@JS('Deno')
external JSObject? get _denoGlobal;

extension type DenoHostObject._(JSObject _) implements JSObject {}

extension type DenoGlobal._(JSObject _) implements JSObject {
  external DenoVersion? get version;

  @JS('serve')
  external JSFunction? get serveMember;

  @JS('upgradeWebSocket')
  external JSFunction? get upgradeWebSocketMember;

  external DenoHttpServerHost serve(
    DenoServeTcpOptions options,
    JSFunction handler,
  );
}

extension type DenoVersion._(JSObject _) implements JSObject {
  external JSString? get deno;
}

extension type DenoHttpServerHost._(JSObject _) implements JSObject {
  external DenoNetAddr get addr;
  external JSPromise<JSAny?> get finished;
  external JSPromise<JSAny?> shutdown();
}

extension type DenoNetAddr._(JSObject _) implements JSObject {
  external JSString get hostname;
  external JSNumber get port;
}

extension type DenoUpgradeWebSocketOptions._(JSObject _) implements JSObject {
  external factory DenoUpgradeWebSocketOptions({String protocol});
}

extension type DenoUpgradeWebSocketResult._(JSObject _) implements JSObject {
  external web.Response get response;
  external web.WebSocket get socket;
}

extension type DenoServeTcpOptions._(JSObject _) implements JSObject {
  external factory DenoServeTcpOptions({
    String hostname,
    int port,
    JSFunction onListen,
  });
}

DenoHostObject? get globalThis => DenoHostObject._(_globalThis);

DenoGlobal? get denoGlobal {
  final value = _denoGlobal;
  if (value == null) {
    return null;
  }

  return DenoGlobal._(value);
}

String? denoRuntimeVersion(DenoGlobal deno) => deno.version?.deno?.toDart;

bool denoHasServe(DenoGlobal deno) => deno.serveMember != null;

bool denoHasUpgradeWebSocket(DenoGlobal deno) =>
    deno.upgradeWebSocketMember != null;

DenoHttpServerHost denoServe(
  DenoGlobal deno, {
  required String host,
  required int port,
  required JSFunction handler,
}) {
  if (!denoHasServe(deno)) {
    throw UnsupportedError(
      'Deno runtime requires Deno.serve, but it is not available on the current host.',
    );
  }

  void onListen([JSAny? _]) {}

  return deno.serve(
    DenoServeTcpOptions(hostname: host, port: port, onListen: onListen.toJS),
    handler,
  );
}

String denoServerHostname(DenoHttpServerHost server) {
  return server.addr.hostname.toDart;
}

int denoServerPort(DenoHttpServerHost server) {
  return server.addr.port.toDartInt;
}

Future<void> denoServerFinished(DenoHttpServerHost server) async {
  await server.finished.toDart;
}

Future<void> shutdownDenoServer(DenoHttpServerHost server) async {
  await server.shutdown().toDart;
}

DenoUpgradeWebSocketResult denoUpgradeWebSocket(
  DenoGlobal deno,
  web.Request request, {
  String? protocol,
}) {
  final member = deno.upgradeWebSocketMember;
  if (member == null) {
    throw UnsupportedError(
      'Deno runtime requires Deno.upgradeWebSocket, but it is not available on the current host.',
    );
  }

  final result = switch (protocol) {
    null => member.callAsFunction(deno, request),
    _ => member.callAsFunction(
      deno,
      request,
      DenoUpgradeWebSocketOptions(protocol: protocol),
    ),
  };

  return DenoUpgradeWebSocketResult._(result as JSObject);
}
