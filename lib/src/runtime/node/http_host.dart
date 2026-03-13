// ignore_for_file: public_member_api_docs

@JS()
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'interop.dart';

@JS('require')
external JSFunction? get nodeRequire;

extension type NodeHttpModuleHost._(JSObject _) implements JSObject {
  @JS('createServer')
  external JSFunction get createServer;
}

extension type NodeHttpServerHost._(JSObject _) implements JSObject {
  external JSFunction get listen;
  external JSFunction get close;
  external JSFunction get on;
  external JSFunction get address;
}

extension type NodeIncomingMessageHost._(JSObject _) implements JSObject {
  external JSAny? get method;
  external JSAny? get url;
  external JSAny? get headers;
  external JSFunction get on;
  external JSFunction get once;
  @JS('removeListener')
  external JSFunction get removeListener;
}

extension type NodeServerResponseHost._(JSObject _) implements JSObject {
  external set statusCode(JSAny? value);
  external set statusMessage(JSAny? value);

  @JS('writeHead')
  external JSFunction get writeHead;

  @JS('setHeader')
  external JSFunction get setHeader;

  @JS('removeListener')
  external JSFunction get removeListener;

  external JSFunction get once;
  external JSFunction get write;
  external JSFunction get end;
}

final class NodeHttpBinding {
  const NodeHttpBinding({required this.host, required this.port});

  final String host;
  final int port;
}

typedef NodeHostRequestListener =
    void Function(
      NodeIncomingMessageHost request,
      NodeServerResponseHost response,
    );

NodeHttpModuleHost? get nodeHttpModule {
  final process = nodeProcess;
  final getBuiltinModule = process?.getBuiltinModule;
  if (getBuiltinModule != null) {
    final module = getBuiltinModule.callAsFunction(process, 'node:http'.toJS);
    if (module != null) {
      return NodeHttpModuleHost._(module as JSObject);
    }
  }

  final require = nodeRequire;
  if (require == null) {
    return null;
  }

  final module = require.callAsFunction(null, 'node:http'.toJS);
  if (module == null) {
    return null;
  }

  return NodeHttpModuleHost._(module as JSObject);
}

String? nodeIncomingMessageMethod(NodeIncomingMessageHost request) {
  final method = request.method;
  if (method == null) {
    return null;
  }

  return (method as JSString).toDart;
}

String? nodeIncomingMessageUrl(NodeIncomingMessageHost request) {
  final url = request.url;
  if (url == null) {
    return null;
  }

  return (url as JSString).toDart;
}

Object? nodeIncomingMessageHeaders(NodeIncomingMessageHost request) {
  final headers = request.headers;
  return headers?.dartify();
}

Stream<List<int>> nodeIncomingMessageBody(NodeIncomingMessageHost request) {
  late final StreamController<List<int>> controller;
  var settled = false;
  var listening = false;
  JSFunction? onData;
  JSFunction? onEnd;
  JSFunction? onError;
  JSFunction? onAborted;

  void detachListeners() {
    if (!listening) {
      return;
    }

    void remove(String event, JSFunction? listener) {
      if (listener == null) {
        return;
      }
      request.removeListener.callAsFunction(request, event.toJS, listener);
    }

    remove('data', onData);
    remove('end', onEnd);
    remove('error', onError);
    remove('aborted', onAborted);

    onData = null;
    onEnd = null;
    onError = null;
    onAborted = null;
    listening = false;
  }

  void settleDone() {
    if (settled) {
      return;
    }

    detachListeners();

    if (!controller.isClosed) {
      controller.close();
    }
    settled = true;
  }

  void settleError(Object error) {
    if (settled) {
      return;
    }

    detachListeners();

    if (!controller.isClosed) {
      controller.addError(error);
      controller.close();
    }
    settled = true;
  }

  controller = StreamController<List<int>>(
    sync: true,
    onListen: () {
      if (settled || listening) {
        return;
      }

      onData = ((JSAny? chunk) {
        if (settled || chunk == null) {
          return;
        }

        final bytes = _bytesFromNodeChunk(chunk);
        if (bytes == null) {
          return;
        }

        controller.add(bytes);
      }).toJS;
      onEnd = (() {
        settleDone();
      }).toJS;
      onError = ((JSAny? error) {
        settleError(StateError(_describeJsError(error)));
      }).toJS;
      onAborted = (() {
        settleError(StateError('Node request body was aborted.'));
      }).toJS;

      request.on.callAsFunction(request, 'data'.toJS, onData);
      request.on.callAsFunction(request, 'end'.toJS, onEnd);
      request.on.callAsFunction(request, 'error'.toJS, onError);
      request.on.callAsFunction(request, 'aborted'.toJS, onAborted);
      listening = true;
    },
    onCancel: () {
      if (settled) {
        return;
      }

      detachListeners();
      settled = true;
    },
  );

  return controller.stream;
}

NodeHttpServerHost createNodeHttpServer(
  NodeHttpModuleHost module, {
  required NodeHostRequestListener onRequest,
}) {
  final server = module.createServer.callAsFunction(
    module,
    ((NodeIncomingMessageHost request, NodeServerResponseHost response) {
      onRequest(request, response);
    }).toJS,
  );

  return NodeHttpServerHost._(server as JSObject);
}

Future<NodeHttpBinding> listenNodeHttpServer(
  NodeHttpServerHost server, {
  required String host,
  required int port,
}) async {
  final completer = Completer<NodeHttpBinding>();

  server.on.callAsFunction(
    server,
    'error'.toJS,
    ((JSAny? error) {
      if (completer.isCompleted) {
        return;
      }

      completer.completeError(StateError(_describeJsError(error)));
    }).toJS,
  );

  server.listen.callAsFunction(
    server,
    port.toJS,
    host.toJS,
    (() {
      if (completer.isCompleted) {
        return;
      }

      final resolved = _serverBindingFromAddress(
        server,
        fallbackHost: host,
        fallbackPort: port,
      );
      completer.complete(resolved);
    }).toJS,
  );

  return completer.future;
}

Future<void> closeNodeHttpServer(NodeHttpServerHost server) async {
  final completer = Completer<void>();

  server.close.callAsFunction(
    server,
    (([JSAny? error]) {
      if (completer.isCompleted) {
        return;
      }

      if (error?.isDefinedAndNotNull ?? false) {
        completer.completeError(StateError(_describeJsError(error)));
        return;
      }

      completer.complete();
    }).toJS,
  );

  return completer.future;
}

void nodeServerResponseSetStatus(
  NodeServerResponseHost response, {
  required int status,
  required String statusText,
}) {
  response.statusCode = status.toJS;
  response.statusMessage = statusText.toJS;
}

void nodeServerResponseSetHeader(
  NodeServerResponseHost response,
  String name,
  Object value,
) {
  response.setHeader.callAsFunction(response, name.toJS, switch (value) {
    String() => value.toJS,
    List<String>() => value.map((entry) => entry.toJS).toList().toJS,
    _ => value.jsify(),
  });
}

void nodeServerResponseWriteHead(
  NodeServerResponseHost response, {
  required int status,
  String? statusText,
  List<String>? rawHeaders,
}) {
  final jsStatus = status.toJS;
  final jsRawHeaders = rawHeaders?.map((entry) => entry.toJS).toList().toJS;

  if (statusText != null && statusText.isNotEmpty) {
    if (jsRawHeaders != null) {
      response.writeHead.callAsFunction(
        response,
        jsStatus,
        statusText.toJS,
        jsRawHeaders,
      );
      return;
    }

    response.writeHead.callAsFunction(response, jsStatus, statusText.toJS);
    return;
  }

  if (jsRawHeaders != null) {
    response.writeHead.callAsFunction(response, jsStatus, jsRawHeaders);
    return;
  }

  response.writeHead.callAsFunction(response, jsStatus);
}

Future<void> nodeServerResponseWrite(
  NodeServerResponseHost response,
  Object body,
) async {
  final completer = Completer<void>();
  var settled = false;
  late final JSExportedDartFunction onError;

  onError = ((JSAny? error) {
    if (settled) {
      return;
    }

    settled = true;
    completer.completeError(StateError(_describeJsError(error)));
  }).toJS;

  response.once.callAsFunction(response, 'error'.toJS, onError);

  response.write.callAsFunction(
    response,
    _jsBody(body),
    (() {
      response.removeListener.callAsFunction(response, 'error'.toJS, onError);
      if (settled || completer.isCompleted) {
        return;
      }

      settled = true;
      completer.complete();
    }).toJS,
  );
  return completer.future;
}

Future<void> nodeServerResponseEnd(
  NodeServerResponseHost response, [
  Object? body,
]) async {
  final completer = Completer<void>();
  var settled = false;
  late final JSExportedDartFunction onError;

  onError = ((JSAny? error) {
    if (settled) {
      return;
    }

    settled = true;
    completer.completeError(StateError(_describeJsError(error)));
  }).toJS;

  response.once.callAsFunction(response, 'error'.toJS, onError);

  final callback = (() {
    response.removeListener.callAsFunction(response, 'error'.toJS, onError);
    if (settled || completer.isCompleted) {
      return;
    }

    settled = true;
    completer.complete();
  }).toJS;

  if (body == null) {
    response.end.callAsFunction(response, callback);
    return completer.future;
  }

  response.end.callAsFunction(response, _jsBody(body), callback);
  return completer.future;
}

NodeHttpBinding _serverBindingFromAddress(
  NodeHttpServerHost server, {
  required String fallbackHost,
  required int fallbackPort,
}) {
  final address = server.address.callAsFunction(server);
  if (address == null || address.isA<JSString>()) {
    return NodeHttpBinding(host: fallbackHost, port: fallbackPort);
  }

  final object = address as JSObject;
  final port =
      object.getProperty<JSNumber?>('port'.toJS)?.toDartInt ?? fallbackPort;
  final host =
      object.getProperty<JSString?>('address'.toJS)?.toDart ?? fallbackHost;
  return NodeHttpBinding(host: host, port: port);
}

Uint8List? _bytesFromNodeChunk(JSAny chunk) {
  if (chunk.isA<JSUint8Array>()) {
    return (chunk as JSUint8Array).toDart;
  }

  if (chunk.isA<JSArrayBuffer>()) {
    return (chunk as JSArrayBuffer).toDart.asUint8List();
  }

  if (chunk.isA<JSString>()) {
    return Uint8List.fromList(utf8.encode((chunk as JSString).toDart));
  }

  final dartValue = chunk.dartify();
  return switch (dartValue) {
    null => null,
    Uint8List() => dartValue,
    ByteBuffer() => dartValue.asUint8List(),
    List<int>() => Uint8List.fromList(dartValue),
    String() => Uint8List.fromList(utf8.encode(dartValue)),
    _ => null,
  };
}

JSAny _jsBody(Object body) {
  return switch (body) {
    Uint8List() => body.toJS,
    List<int>() => Uint8List.fromList(body).toJS,
    String() => body.toJS,
    _ => throw ArgumentError.value(
      body,
      'body',
      'Unsupported Node.js response body type.',
    ),
  };
}

String _describeJsError(JSAny? error) {
  if (error == null) {
    return 'Unknown Node.js host error.';
  }

  final dartValue = error.dartify();
  return dartValue?.toString() ?? error.toString();
}
