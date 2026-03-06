import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

final class NodeHttpModuleHost {
  const NodeHttpModuleHost();
}

final class NodeHttpServerHost {
  const NodeHttpServerHost({this.port, this.address});

  final int? port;
  final String? address;
}

final class NodeHttpBinding {
  const NodeHttpBinding({required this.host, required this.port});

  final String host;
  final int port;
}

final class NodeIncomingMessageHost {
  const NodeIncomingMessageHost({
    this.method,
    this.url,
    this.headers,
    this.body,
    this.bodyError,
  });

  final String? method;
  final String? url;
  final Map<String, Object?>? headers;
  final Object? body;
  final Object? bodyError;
}

final class NodeServerResponseHost {
  NodeServerResponseHost({
    this.statusCode = 200,
    this.statusMessage = 'OK',
    this.writeError,
    this.endError,
  });

  int statusCode;
  String statusMessage;
  final Map<String, Object?> headers = <String, Object?>{};
  final List<List<int>> chunks = <List<int>>[];
  bool ended = false;
  final Object? writeError;
  final Object? endError;
}

typedef NodeHostRequestListener =
    void Function(
      NodeIncomingMessageHost request,
      NodeServerResponseHost response,
    );

NodeHttpModuleHost? get nodeHttpModule => null;

String? nodeIncomingMessageMethod(NodeIncomingMessageHost request) {
  return request.method;
}

String? nodeIncomingMessageUrl(NodeIncomingMessageHost request) {
  return request.url;
}

Object? nodeIncomingMessageHeaders(NodeIncomingMessageHost request) {
  return request.headers;
}

Object? nodeIncomingMessageBody(NodeIncomingMessageHost request) {
  return request.body;
}

Future<Object?> readNodeIncomingMessageBody(
  NodeIncomingMessageHost request,
) async {
  if (request.bodyError != null) {
    return Stream<List<int>>.error(request.bodyError!);
  }

  return request.body;
}

NodeHttpServerHost createNodeHttpServer(
  NodeHttpModuleHost module, {
  required NodeHostRequestListener onRequest,
}) {
  module;
  onRequest;
  return const NodeHttpServerHost();
}

Future<NodeHttpBinding> listenNodeHttpServer(
  NodeHttpServerHost server, {
  required String host,
  required int port,
}) async {
  return NodeHttpBinding(
    host: server.address ?? host,
    port: server.port ?? port,
  );
}

Future<void> closeNodeHttpServer(NodeHttpServerHost server) async {
  server;
}

void nodeServerResponseSetStatus(
  NodeServerResponseHost response, {
  required int status,
  required String statusText,
}) {
  response
    ..statusCode = status
    ..statusMessage = statusText;
}

void nodeServerResponseSetHeader(
  NodeServerResponseHost response,
  String name,
  Object value,
) {
  response.headers[name] = value;
}

Future<void> nodeServerResponseWrite(
  NodeServerResponseHost response,
  Object body,
) async {
  if (response.writeError != null) {
    throw StateError(response.writeError.toString());
  }

  response.chunks.add(_bytesFromBody(body));
}

Future<void> nodeServerResponseEnd(
  NodeServerResponseHost response, [
  Object? body,
]) async {
  if (response.endError != null) {
    throw StateError(response.endError.toString());
  }

  response.ended = true;
  if (body == null) {
    return;
  }

  response.chunks.add(_bytesFromBody(body));
}

List<int> _bytesFromBody(Object body) {
  return switch (body) {
    Uint8List() => body,
    List<int>() => body,
    String() => utf8.encode(body),
    _ => throw ArgumentError.value(
      body,
      'body',
      'Unsupported stub node response body type.',
    ),
  };
}
