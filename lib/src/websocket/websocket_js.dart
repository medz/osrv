import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:ht/ht.dart' show Response;

import '../request.dart';
import '../types.dart';
import '../websocket_contract.dart';

@JS('globalThis')
external JSObject get _globalThis;

const String _wsRegisterPendingKey = '__osrv_ws_register_pending__';
const String _wsSendKey = '__osrv_ws_send__';
const String _wsOnOpenKey = '__osrv_ws_on_open__';
const String _wsOnMessageKey = '__osrv_ws_on_message__';
const String _wsOnCloseKey = '__osrv_ws_on_close__';
const String _wsOnErrorKey = '__osrv_ws_on_error__';
const String _wsUpgradeHeader = 'x-osrv-upgrade';
const String _wsUpgradeValue = 'websocket';

const int _webSocketMessageTooBig = 1009;

final Map<String, _JsBridgeServerWebSocket> _socketsById =
    <String, _JsBridgeServerWebSocket>{};

int _socketSequence = 0;
bool _callbacksBound = false;

Future<ServerWebSocket> upgradeWebSocket(
  ServerRequest request, {
  WebSocketLimits limits = const WebSocketLimits(),
}) async {
  if (request.isWebSocketUpgraded) {
    throw StateError('Request has already been upgraded to websocket.');
  }

  final requestId = _extractRequestId(request);
  if (requestId == null) {
    throw UnsupportedError(
      'Request runtime does not expose websocket upgrade metadata.',
    );
  }

  _ensureCallbacksBound();

  final socketId = _nextSocketId();
  final socket = _JsBridgeServerWebSocket(socketId, limits);

  final registered = _registerPendingUpgrade(requestId, socketId);
  if (!registered) {
    throw UnsupportedError(
      'Runtime adapter does not expose websocket registration hooks.',
    );
  }

  _socketsById[socketId] = socket;
  request.markWebSocketUpgraded();
  request.setRawWebSocket(socketId);
  return socket;
}

String _nextSocketId() {
  _socketSequence += 1;
  return 'osrv-ws-$_socketSequence-${DateTime.now().microsecondsSinceEpoch}';
}

String? _extractRequestId(ServerRequest request) {
  final runtime = request.runtime;
  if (runtime == null) {
    return null;
  }

  final candidates = <Object?>[
    runtime.raw.node,
    runtime.raw.bun,
    runtime.raw.deno,
    runtime.raw.cloudflare,
    runtime.raw.vercel,
    runtime.raw.netlify,
  ];

  for (final raw in candidates) {
    if (raw is! Map) {
      continue;
    }

    final id = raw['requestId'];
    if (id is String && id.isNotEmpty) {
      return id;
    }
  }

  return null;
}

bool _registerPendingUpgrade(String requestId, String socketId) {
  final register = _globalThis.getProperty(_wsRegisterPendingKey.toJS);
  if (!register.isA<JSFunction>()) {
    return false;
  }

  try {
    (register as JSFunction).callAsFunction(
      register,
      requestId.toJS,
      socketId.toJS,
    );
    return true;
  } catch (_) {
    return false;
  }
}

void _ensureCallbacksBound() {
  if (_callbacksBound) {
    return;
  }

  _globalThis.setProperty(
    _wsOnOpenKey.toJS,
    ((JSAny? socketId) {
      final id = _asString(socketId);
      if (id == null) {
        return;
      }
      _socketsById[id]?._onOpen();
    }).toJS,
  );

  _globalThis.setProperty(
    _wsOnMessageKey.toJS,
    ((JSAny? socketId, JSAny? kind, JSAny? payload) {
      final id = _asString(socketId);
      final messageKind = _asString(kind);
      final value = _asString(payload);
      if (id == null || messageKind == null || value == null) {
        return;
      }
      _socketsById[id]?._onMessage(messageKind, value);
    }).toJS,
  );

  _globalThis.setProperty(
    _wsOnCloseKey.toJS,
    ((JSAny? socketId, JSAny? code, JSAny? reason) {
      final id = _asString(socketId);
      if (id == null) {
        return;
      }
      final codeValue = int.tryParse(_asString(code) ?? '');
      final reasonValue = _asString(reason);
      _socketsById[id]?._onClose(code: codeValue, reason: reasonValue);
    }).toJS,
  );

  _globalThis.setProperty(
    _wsOnErrorKey.toJS,
    ((JSAny? socketId, JSAny? reason) {
      final id = _asString(socketId);
      final value = _asString(reason);
      if (id == null || value == null) {
        return;
      }
      _socketsById[id]?._onError(value);
    }).toJS,
  );

  _callbacksBound = true;
}

String? _asString(JSAny? value) {
  if (value == null || !value.isA<JSString>()) {
    return null;
  }
  return (value as JSString).toDart;
}

Future<void> _sendSocketCommand(
  String socketId, {
  required String action,
  String? text,
  List<int>? bytes,
  int? code,
  String? reason,
}) {
  final send = _globalThis.getProperty(_wsSendKey.toJS);
  if (!send.isA<JSFunction>()) {
    throw UnsupportedError('Runtime websocket send hook is not available.');
  }

  final payload = <String, Object?>{
    'socketId': socketId,
    'action': action,
    ...?(text == null ? null : <String, Object?>{'text': text}),
    ...?(bytes == null
        ? null
        : <String, Object?>{'bytesBase64': base64Encode(bytes)}),
    ...?(code == null ? null : <String, Object?>{'code': code}),
    ...?(reason == null ? null : <String, Object?>{'reason': reason}),
  };

  final completer = Completer<void>();
  final resolve = ((JSAny? _) {
    if (!completer.isCompleted) {
      completer.complete();
    }
  }).toJS;
  final reject = ((JSAny? _) {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError('Runtime rejected websocket command `$action`.'),
      );
    }
  }).toJS;

  (send as JSFunction).callAsFunction(
    send,
    jsonEncode(payload).toJS,
    resolve,
    reject,
  );

  return completer.future;
}

final class _JsBridgeServerWebSocket implements ServerWebSocket {
  _JsBridgeServerWebSocket(this._socketId, this._limits);

  final String _socketId;
  final WebSocketLimits _limits;
  final StreamController<Object> _messagesController =
      StreamController<Object>.broadcast();
  final Queue<_PendingFrame> _pendingFrames = Queue<_PendingFrame>();
  final Completer<void> _doneCompleter = Completer<void>();

  bool _open = false;
  bool _closed = false;
  int _bufferedBytes = 0;
  Future<void> _sendChain = Future<void>.value();

  @override
  Stream<Object> get messages => _messagesController.stream;

  @override
  bool get isOpen => _open && !_closed;

  @override
  Future<void> sendText(String data) async {
    _assertNotClosed();
    final size = utf8.encode(data).length;
    _validateFrameSize(size);
    await _sendOrQueue(_PendingFrame.text(data, size));
  }

  @override
  Future<void> sendBytes(List<int> data) async {
    _assertNotClosed();
    final size = data.length;
    _validateFrameSize(size);
    await _sendOrQueue(_PendingFrame.binary(List<int>.from(data), size));
  }

  @override
  Future<void> close({int? code, String? reason}) async {
    if (_closed) {
      return;
    }

    _closed = true;
    _open = false;
    _pendingFrames.clear();
    _bufferedBytes = 0;

    try {
      await _enqueueSend(() {
        return _sendSocketCommand(
          _socketId,
          action: 'close',
          code: code,
          reason: reason,
        );
      });
    } catch (_) {
      // Ignore transport close errors: the runtime may already be down.
    } finally {
      _finish();
    }
  }

  @override
  Future<void> done() => _doneCompleter.future;

  @override
  Response toResponse() {
    final response = Response.empty();
    response.headers.set(_wsUpgradeHeader, _wsUpgradeValue);
    return response;
  }

  void _onOpen() {
    if (_closed) {
      return;
    }

    _open = true;
    if (_pendingFrames.isEmpty) {
      return;
    }

    final pending = _pendingFrames.toList(growable: false);
    _pendingFrames.clear();
    _bufferedBytes = 0;

    for (final frame in pending) {
      unawaited(_dispatchFrame(frame));
    }
  }

  void _onMessage(String kind, String payload) {
    if (_closed) {
      return;
    }

    switch (kind) {
      case 'text':
        final size = utf8.encode(payload).length;
        if (size > _limits.maxFrameBytes) {
          unawaited(
            close(code: _webSocketMessageTooBig, reason: 'Frame too large'),
          );
          return;
        }
        _messagesController.add(payload);
        break;
      case 'binary':
        final bytes = base64Decode(payload);
        if (bytes.length > _limits.maxFrameBytes) {
          unawaited(
            close(code: _webSocketMessageTooBig, reason: 'Frame too large'),
          );
          return;
        }
        _messagesController.add(bytes);
        break;
      default:
        _messagesController.addError(
          StateError('Unknown websocket message kind: $kind'),
        );
        break;
    }
  }

  void _onClose({int? code, String? reason}) {
    if (_closed && _doneCompleter.isCompleted) {
      return;
    }

    _closed = true;
    _open = false;

    if (reason != null && reason.isNotEmpty) {
      _messagesController.addError(
        StateError(
          code == null
              ? 'WebSocket closed: $reason'
              : 'WebSocket closed ($code): $reason',
        ),
      );
    }
    _finish();
  }

  void _onError(String reason) {
    if (_closed) {
      return;
    }

    _messagesController.addError(StateError(reason));
  }

  Future<void> _sendOrQueue(_PendingFrame frame) async {
    if (!_open) {
      final nextBuffered = _bufferedBytes + frame.sizeBytes;
      if (nextBuffered > _limits.maxBufferedBytes) {
        throw StateError(
          'WebSocket buffered bytes exceed maxBufferedBytes '
          '(${_limits.maxBufferedBytes}).',
        );
      }
      _bufferedBytes = nextBuffered;
      _pendingFrames.add(frame);
      return;
    }

    await _dispatchFrame(frame);
  }

  Future<void> _dispatchFrame(_PendingFrame frame) {
    return _enqueueSend(() async {
      switch (frame.kind) {
        case _PendingFrameKind.text:
          await _sendSocketCommand(
            _socketId,
            action: 'text',
            text: frame.text!,
          );
          break;
        case _PendingFrameKind.binary:
          await _sendSocketCommand(
            _socketId,
            action: 'binary',
            bytes: frame.bytes!,
          );
          break;
      }
    });
  }

  Future<void> _enqueueSend(Future<void> Function() operation) {
    final next = _sendChain.then((_) => operation());
    _sendChain = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        error;
        stackTrace;
      },
    );
    return next;
  }

  void _validateFrameSize(int size) {
    if (size <= _limits.maxFrameBytes) {
      return;
    }

    throw StateError(
      'WebSocket frame exceeds maxFrameBytes (${_limits.maxFrameBytes}).',
    );
  }

  void _assertNotClosed() {
    if (!_closed) {
      return;
    }
    throw StateError('WebSocket is closed.');
  }

  void _finish() {
    _socketsById.remove(_socketId);
    if (!_messagesController.isClosed) {
      unawaited(_messagesController.close());
    }
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }
}

enum _PendingFrameKind { text, binary }

final class _PendingFrame {
  const _PendingFrame.text(this.text, this.sizeBytes)
    : kind = _PendingFrameKind.text,
      bytes = null;

  const _PendingFrame.binary(this.bytes, this.sizeBytes)
    : kind = _PendingFrameKind.binary,
      text = null;

  final _PendingFrameKind kind;
  final String? text;
  final List<int>? bytes;
  final int sizeBytes;
}
