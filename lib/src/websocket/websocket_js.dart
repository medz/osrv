import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:ht/ht.dart' show Headers, Response;
import 'package:web/web.dart' as web;

import '../request.dart';
import '../runtime/js/global.dart';
import 'internal.dart';
import '../websocket_contract.dart';

const String _runtimeNode = 'node';
const String _runtimeBun = 'bun';
const String _runtimeDeno = 'deno';
const String _runtimeCloudflare = 'cloudflare';
const String _runtimeVercel = 'vercel';
const String _runtimeNetlify = 'netlify';

final Map<String, _JsServerWebSocket> _bunSocketsById =
    <String, _JsServerWebSocket>{};
int _bunSocketSequence = 0;

extension type BunWebSocketHandlers._(JSObject _) implements JSObject {
  external factory BunWebSocketHandlers({
    JSFunction? open,
    JSFunction? message,
    JSFunction? close,
    JSFunction? error,
  });
}

@JS('Deno')
extension type _DenoGlobal._(JSObject _) implements JSObject {
  external _DenoUpgradeResult upgradeWebSocket(web.Request request);
}

extension type _DenoUpgradeResult._(JSObject _) implements JSObject {
  external web.Response get response;
  external web.WebSocket get socket;
}

@JS('WebSocketPair')
external JSFunction get _webSocketPairConstructor;

extension type _CloudflareWebSocket._(JSObject _)
    implements web.WebSocket, JSObject {
  external void accept();
}

extension type _CloudflareResponseInit._(JSObject _) implements JSObject {
  external factory _CloudflareResponseInit({
    int status,
    web.WebSocket webSocket,
  });
}

@JS('Response')
extension type _ResponseCtor._(JSObject _) implements JSObject {
  external factory _ResponseCtor(JSAny? body, JSObject init);
}

Future<ServerWebSocket> upgradeWebSocket(ServerRequest request) {
  final runtime = (request.context[jsRuntimeKey] as String?) ?? '';

  return switch (runtime) {
    _runtimeBun => Future<ServerWebSocket>.value(_upgradeBunWebSocket(request)),
    _runtimeDeno || _runtimeNetlify => Future<ServerWebSocket>.value(
      _upgradeDenoWebSocket(request),
    ),
    _runtimeCloudflare => Future<ServerWebSocket>.value(
      _upgradeCloudflareWebSocket(request),
    ),
    _runtimeVercel => Future<ServerWebSocket>.error(
      UnsupportedError(
        'Vercel Edge runtime does not support websocket upgrade.',
      ),
    ),
    _runtimeNode => Future<ServerWebSocket>.error(
      UnsupportedError(
        'Node websocket upgrade is not implemented in osrv yet.',
      ),
    ),
    _ => Future<ServerWebSocket>.error(
      UnsupportedError(
        'Websocket upgrade is not available in this JS runtime.',
      ),
    ),
  };
}

Response webSocketUpgradeErrorResponse(String message) {
  return Response.text(
    message,
    status: 501,
    headers: Headers({'content-type': 'text/plain; charset=utf-8'}),
  );
}

BunWebSocketHandlers createBunWebSocketHandlers() {
  return BunWebSocketHandlers(
    open: _onBunSocketOpen.toJS,
    message: _onBunSocketMessage.toJS,
    close: _onBunSocketClose.toJS,
    error: _onBunSocketError.toJS,
  );
}

void _onBunSocketOpen(JSAny? socketAny) {
  final socket = _asObject(socketAny);
  if (socket == null) {
    return;
  }

  final id = _bunSocketId(socket);
  if (id == null) {
    return;
  }

  final serverSocket = _bunSocketsById[id];
  if (serverSocket == null) {
    return;
  }

  serverSocket.attachBunSocket(socket);
  serverSocket.markOpen();
}

void _onBunSocketMessage(JSAny? socketAny, JSAny? messageAny) {
  final socket = _asObject(socketAny);
  if (socket == null) {
    return;
  }

  final id = _bunSocketId(socket);
  if (id == null) {
    return;
  }

  final serverSocket = _bunSocketsById[id];
  if (serverSocket == null) {
    return;
  }

  final message = _jsMessageToDart(messageAny);
  if (message == null) {
    return;
  }
  serverSocket.addMessage(message);
}

void _onBunSocketClose(JSAny? socketAny, JSAny? codeAny, JSAny? reasonAny) {
  final socket = _asObject(socketAny);
  if (socket == null) {
    return;
  }

  final id = _bunSocketId(socket);
  if (id == null) {
    return;
  }

  final serverSocket = _bunSocketsById.remove(id);
  if (serverSocket == null) {
    return;
  }

  final reason = _asString(reasonAny);
  final code = _asInt(codeAny);
  serverSocket.markClosed(code: code, reason: reason);
}

void _onBunSocketError(JSAny? socketAny) {
  final socket = _asObject(socketAny);
  if (socket == null) {
    return;
  }

  final id = _bunSocketId(socket);
  if (id == null) {
    return;
  }

  final serverSocket = _bunSocketsById[id];
  if (serverSocket == null) {
    return;
  }

  serverSocket.addError(StateError('Bun websocket transport error.'));
}

ServerWebSocket _upgradeBunWebSocket(ServerRequest request) {
  final rawRequest = request.context[jsRawRequestKey];
  final rawServer = request.context[jsRawServerKey];
  final runtimeRequest = _asObject(rawRequest);
  final runtimeServer = _asObject(rawServer);

  if (runtimeRequest == null || runtimeServer == null) {
    throw UnsupportedError(
      'Bun websocket upgrade requires request/server runtime handles.',
    );
  }

  final id = 'bun-ws-${_bunSocketSequence++}';
  final pending = _BunPendingUpgrade(
    id: id,
    request: runtimeRequest,
    server: runtimeServer,
  );

  final socket = _JsServerWebSocket(runtime: _runtimeBun, pending: pending);

  request.context[jsPendingWebSocketKey] = _BunPendingUpgradeHolder(
    id: id,
    socket: socket,
    pending: pending,
  );

  return socket;
}

ServerWebSocket _upgradeDenoWebSocket(ServerRequest request) {
  final rawRequest = request.context[jsRawRequestKey] as web.Request?;
  if (rawRequest == null) {
    throw UnsupportedError(
      'Deno websocket upgrade requires native web.Request.',
    );
  }

  final socket = _JsServerWebSocket(
    runtime: _runtimeDeno,
    pending: _DenoPendingUpgrade(rawRequest),
  );

  request.context[jsPendingWebSocketKey] = _SimplePendingUpgradeHolder(
    socket: socket,
    pending: socket.pending,
  );

  return socket;
}

ServerWebSocket _upgradeCloudflareWebSocket(ServerRequest request) {
  final socket = _JsServerWebSocket(
    runtime: _runtimeCloudflare,
    pending: _CloudflarePendingUpgrade(),
  );

  request.context[jsPendingWebSocketKey] = _SimplePendingUpgradeHolder(
    socket: socket,
    pending: socket.pending,
  );

  return socket;
}

abstract interface class _PendingUpgradeHolder
    implements JsPendingWebSocketUpgrade {
  _JsServerWebSocket get socket;
}

final class _SimplePendingUpgradeHolder implements _PendingUpgradeHolder {
  _SimplePendingUpgradeHolder({required this.socket, required this.pending});

  @override
  final _JsServerWebSocket socket;
  final _JsPendingUpgrade pending;

  @override
  Future<Object?> accept() async {
    final result = await pending.accept(socket);
    socket.attachSocket(result.socket);
    socket.markOpen();
    return result.response;
  }
}

final class _BunPendingUpgradeHolder implements _PendingUpgradeHolder {
  _BunPendingUpgradeHolder({
    required this.id,
    required this.socket,
    required this.pending,
  });

  final String id;

  @override
  final _JsServerWebSocket socket;
  final _BunPendingUpgrade pending;

  @override
  Future<Object?> accept() async {
    _bunSocketsById[id] = socket;

    final upgraded = pending.server
        .callMethod<JSBoolean>(
          'upgrade'.toJS,
          pending.request,
          pending.upgradeData,
        )
        .toDart;

    if (!upgraded) {
      _bunSocketsById.remove(id);
      throw StateError('Bun refused websocket upgrade request.');
    }

    return null;
  }
}

final class _JsServerWebSocket implements ServerWebSocket {
  _JsServerWebSocket({required this.runtime, required this.pending});

  final String runtime;
  final _JsPendingUpgrade pending;

  final StreamController<Object> _messages =
      StreamController<Object>.broadcast();
  final Completer<void> _done = Completer<void>();
  final List<Object> _sendQueue = <Object>[];

  _SocketAdapter? _socket;
  bool _open = false;
  bool _closed = false;

  @override
  Stream<Object> get messages => _messages.stream;

  @override
  bool get isOpen => _open && !_closed;

  @override
  Future<void> sendText(String data) async {
    _assertNotClosed();
    if (_socket case final socket? when _open) {
      socket.sendText(data);
      return;
    }
    _sendQueue.add(data);
  }

  @override
  Future<void> sendBytes(List<int> data) async {
    _assertNotClosed();
    final bytes = Uint8List.fromList(data);
    if (_socket case final socket? when _open) {
      socket.sendBytes(bytes);
      return;
    }
    _sendQueue.add(bytes);
  }

  @override
  Future<void> close({int? code, String? reason}) async {
    if (_closed) {
      return;
    }

    _closed = true;
    _open = false;

    final socket = _socket;
    if (socket != null) {
      socket.close(code: code, reason: reason);
    }

    await _finish();
  }

  @override
  Future<void> done() => _done.future;

  @override
  Response toResponse() {
    final response = Response.empty(status: 101, headers: Headers());
    response.headers.set(websocketUpgradeHeader, websocketUpgradeValue);
    return response;
  }

  void attachSocket(_SocketAdapter socket) {
    _socket = socket;
  }

  void attachBunSocket(JSObject socket) {
    _socket = _BunSocketAdapter(socket);
  }

  void markOpen() {
    if (_closed) {
      return;
    }

    _open = true;
    final socket = _socket;
    if (socket == null) {
      return;
    }

    for (final queued in _sendQueue) {
      if (queued is String) {
        socket.sendText(queued);
      } else if (queued is Uint8List) {
        socket.sendBytes(queued);
      }
    }
    _sendQueue.clear();
  }

  void addMessage(Object message) {
    if (_closed) {
      return;
    }
    _messages.add(message);
  }

  void addError(Object error) {
    if (_closed) {
      return;
    }
    _messages.addError(error);
  }

  void markClosed({int? code, String? reason}) {
    if (_closed) {
      return;
    }

    _closed = true;
    _open = false;

    if (reason != null && reason.isNotEmpty) {
      if (code == null) {
        _messages.addError(StateError('WebSocket closed: $reason'));
      } else {
        _messages.addError(StateError('WebSocket closed ($code): $reason'));
      }
    }

    unawaited(_finish());
  }

  Future<void> _finish() async {
    if (!_messages.isClosed) {
      await _messages.close();
    }
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  void _assertNotClosed() {
    if (_closed) {
      throw StateError('WebSocket is closed.');
    }
  }
}

sealed class _JsPendingUpgrade {
  Future<_AcceptedUpgrade> accept(_JsServerWebSocket socket);
}

final class _DenoPendingUpgrade implements _JsPendingUpgrade {
  _DenoPendingUpgrade(this.request);

  final web.Request request;

  @override
  Future<_AcceptedUpgrade> accept(_JsServerWebSocket socket) async {
    final denoAny = globalThis.Deno;
    if (denoAny == null) {
      throw UnsupportedError(
        'Deno global is unavailable for websocket upgrade.',
      );
    }

    final result = _DenoGlobal._(denoAny).upgradeWebSocket(request);
    final runtimeSocket = result.socket;
    _bindWebSocketEvents(runtimeSocket, socket);

    return _AcceptedUpgrade(
      response: result.response,
      socket: _WebSocketAdapter(runtimeSocket),
    );
  }
}

final class _CloudflarePendingUpgrade implements _JsPendingUpgrade {
  @override
  Future<_AcceptedUpgrade> accept(_JsServerWebSocket socket) async {
    if (globalThis.WebSocketPair == null) {
      throw UnsupportedError('WebSocketPair is not available in this runtime.');
    }

    final pairObject = _webSocketPairConstructor.callAsConstructor<JSObject>();
    final clientAny = pairObject.getProperty<JSAny>('0'.toJS);
    final serverAny = pairObject.getProperty<JSAny>('1'.toJS);

    if (!clientAny.isA<web.WebSocket>() || !serverAny.isA<JSObject>()) {
      throw StateError('WebSocketPair returned invalid socket objects.');
    }

    final client = clientAny as web.WebSocket;
    final server = _CloudflareWebSocket._(serverAny as JSObject);

    server.accept();
    _bindWebSocketEvents(server, socket);

    final response =
        _ResponseCtor(
              null,
              _CloudflareResponseInit(status: 101, webSocket: client),
            )
            as web.Response;

    return _AcceptedUpgrade(
      response: response,
      socket: _WebSocketAdapter(server),
    );
  }
}

final class _BunPendingUpgrade implements _JsPendingUpgrade {
  _BunPendingUpgrade({
    required this.id,
    required this.request,
    required this.server,
  }) : upgradeData = _createUpgradeData(id);

  final String id;
  final JSObject request;
  final JSObject server;
  final JSObject upgradeData;

  static JSObject _createUpgradeData(String id) {
    final data = JSObject();
    final inner = JSObject();
    inner.setProperty('id'.toJS, id.toJS);
    data.setProperty('data'.toJS, inner);
    return data;
  }

  @override
  Future<_AcceptedUpgrade> accept(_JsServerWebSocket socket) {
    throw UnsupportedError('Bun pending upgrade must be accepted by holder.');
  }
}

final class _AcceptedUpgrade {
  const _AcceptedUpgrade({required this.response, required this.socket});

  final Object? response;
  final _SocketAdapter socket;
}

abstract class _SocketAdapter {
  void sendText(String data);
  void sendBytes(Uint8List data);
  void close({int? code, String? reason});
}

final class _WebSocketAdapter implements _SocketAdapter {
  _WebSocketAdapter(this._socket);

  final web.WebSocket _socket;

  @override
  void sendText(String data) {
    _socket.send(data.toJS);
  }

  @override
  void sendBytes(Uint8List data) {
    _socket.send(data.toJS);
  }

  @override
  void close({int? code, String? reason}) {
    if (code == null && reason == null) {
      _socket.close();
      return;
    }
    _socket.close(code ?? 1000, reason ?? '');
  }
}

final class _BunSocketAdapter implements _SocketAdapter {
  _BunSocketAdapter(this._socket);

  final JSObject _socket;

  @override
  void sendText(String data) {
    _socket.callMethodVarArgs<JSAny?>('send'.toJS, <JSAny?>[data.toJS]);
  }

  @override
  void sendBytes(Uint8List data) {
    _socket.callMethodVarArgs<JSAny?>('send'.toJS, <JSAny?>[data.toJS]);
  }

  @override
  void close({int? code, String? reason}) {
    final args = <JSAny?>[];
    if (code != null) {
      args.add(code.toJS);
    }
    if (reason != null) {
      args.add(reason.toJS);
    }

    _socket.callMethodVarArgs<JSAny?>('close'.toJS, args);
  }
}

void _bindWebSocketEvents(
  web.WebSocket socket,
  _JsServerWebSocket serverSocket,
) {
  socket.onopen = ((web.Event _) {
    serverSocket.markOpen();
  }).toJS;

  socket.onmessage = ((web.Event event) {
    if (!event.isA<web.MessageEvent>()) {
      return;
    }

    final messageEvent = event as web.MessageEvent;
    final decoded = _jsMessageToDart(messageEvent.data);
    if (decoded != null) {
      serverSocket.addMessage(decoded);
    }
  }).toJS;

  socket.onclose = ((web.Event event) {
    if (event.isA<web.CloseEvent>()) {
      final close = event as web.CloseEvent;
      serverSocket.markClosed(code: close.code, reason: close.reason);
      return;
    }
    serverSocket.markClosed();
  }).toJS;

  socket.onerror = ((web.Event _) {
    serverSocket.addError(StateError('WebSocket runtime error.'));
  }).toJS;
}

Object? _jsMessageToDart(JSAny? value) {
  if (value == null) {
    return null;
  }

  if (value.isA<JSString>()) {
    return (value as JSString).toDart;
  }

  if (value.isA<JSUint8Array>()) {
    return (value as JSUint8Array).toDart;
  }

  if (value.isA<JSArrayBuffer>()) {
    return Uint8List.view((value as JSArrayBuffer).toDart);
  }

  return value.toString();
}

String? _bunSocketId(JSObject socket) {
  final dataAny = socket.getProperty<JSAny?>('data'.toJS);
  if (dataAny == null || !dataAny.isA<JSObject>()) {
    return null;
  }

  final idAny = (dataAny as JSObject).getProperty<JSAny?>('id'.toJS);
  return _asString(idAny);
}

JSObject? _asObject(Object? value) {
  if (value == null) {
    return null;
  }

  try {
    return value as JSObject;
  } catch (_) {
    return null;
  }
}

String? _asString(JSAny? value) {
  if (value != null && value.isA<JSString>()) {
    return (value as JSString).toDart;
  }
  return null;
}

int? _asInt(JSAny? value) {
  if (value != null && value.isA<JSNumber>()) {
    return (value as JSNumber).toDartInt;
  }
  return null;
}
