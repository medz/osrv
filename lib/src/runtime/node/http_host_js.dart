@JS()
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'interop_js.dart';

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
}

extension type NodeServerResponseHost._(JSObject _) implements JSObject {
  external set statusCode(JSAny? value);
  external set statusMessage(JSAny? value);

  @JS('setHeader')
  external JSFunction get setHeader;

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

Object? nodeIncomingMessageBody(NodeIncomingMessageHost request) {
  return null;
}

Future<Object?> readNodeIncomingMessageBody(
  NodeIncomingMessageHost request,
) async {
  final controller = StreamController<List<int>>(sync: true);
  final result = Completer<Object?>();
  var hasBody = false;
  var settled = false;

  void settleError(Object error) {
    if (!result.isCompleted) {
      result.completeError(error);
    }
    if (!controller.isClosed) {
      controller.addError(error);
      controller.close();
    }
    settled = true;
  }

  request.on.callAsFunction(
    request,
    'data'.toJS,
    ((JSAny? chunk) {
      if (chunk == null) {
        return;
      }

      final bytes = _bytesFromNodeChunk(chunk);
      if (bytes == null) {
        return;
      }

      if (!hasBody) {
        hasBody = true;
        if (!result.isCompleted) {
          result.complete(controller.stream);
        }
      }
      controller.add(bytes);
    }).toJS,
  );

  request.once.callAsFunction(
    request,
    'end'.toJS,
    (() {
      if (settled) {
        return;
      }
      if (!result.isCompleted) {
        result.complete(hasBody ? controller.stream : null);
      }
      if (!controller.isClosed) {
        controller.close();
      }
      settled = true;
    }).toJS,
  );

  request.once.callAsFunction(
    request,
    'error'.toJS,
    ((JSAny? error) {
      settleError(StateError(_describeJsError(error)));
    }).toJS,
  );

  request.once.callAsFunction(
    request,
    'aborted'.toJS,
    (() {
      settleError(StateError('Node request body was aborted.'));
    }).toJS,
  );

  return result.future;
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

      if (error != null && error.isDefinedAndNotNull) {
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

Future<void> nodeServerResponseWrite(
  NodeServerResponseHost response,
  Object body,
) async {
  final completer = Completer<void>();
  var settled = false;

  response.once.callAsFunction(
    response,
    'error'.toJS,
    ((JSAny? error) {
      if (settled) {
        return;
      }

      settled = true;
      completer.completeError(StateError(_describeJsError(error)));
    }).toJS,
  );

  response.write.callAsFunction(
    response,
    _jsBody(body),
    (() {
      if (!settled && !completer.isCompleted) {
        settled = true;
        completer.complete();
      }
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

  response.once.callAsFunction(
    response,
    'error'.toJS,
    ((JSAny? error) {
      if (settled) {
        return;
      }

      settled = true;
      completer.completeError(StateError(_describeJsError(error)));
    }).toJS,
  );

  final callback = (() {
    if (!settled && !completer.isCompleted) {
      settled = true;
      completer.complete();
    }
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
