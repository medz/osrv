// ignore_for_file: public_member_api_docs

import 'package:ht/ht.dart' show Headers, HttpMethod, Request, RequestInit;

import 'http_host.dart';

final class NodeRequestHeadSnapshot {
  const NodeRequestHeadSnapshot({
    required this.method,
    required this.url,
    required this.rawHeaders,
    required this.rawBody,
  });

  final String? method;
  final String? url;
  final Object? rawHeaders;
  final Object? rawBody;
}

NodeRequestHeadSnapshot nodeRequestHeadFromHost(
  NodeIncomingMessageHost request,
) {
  return NodeRequestHeadSnapshot(
    method: nodeIncomingMessageMethod(request),
    url: nodeIncomingMessageUrl(request),
    rawHeaders: nodeIncomingMessageHeaders(request),
    rawBody: nodeIncomingMessageBody(request),
  );
}

Future<Request> nodeRequestFromHost(
  NodeIncomingMessageHost request, {
  required Uri origin,
}) async {
  final head = nodeRequestHeadFromHost(request);
  final body = await readNodeIncomingMessageBody(request);
  return nodeRequestFromHeadSnapshot(
    NodeRequestHeadSnapshot(
      method: head.method,
      url: head.url,
      rawHeaders: head.rawHeaders,
      rawBody: body ?? head.rawBody,
    ),
    origin: origin,
  );
}

Request nodeRequestFromHeadSnapshot(
  NodeRequestHeadSnapshot snapshot, {
  required Uri origin,
}) {
  final rawUrl = snapshot.url ?? '/';
  final uri = origin.resolve(rawUrl);

  return Request(
    uri,
    RequestInit(
      method: HttpMethod.parse(snapshot.method ?? 'GET'),
      headers: _headersFromRaw(snapshot.rawHeaders),
      body: _bodyFromRaw(snapshot.rawBody),
    ),
  );
}

Headers _headersFromRaw(Object? rawHeaders) {
  final headers = Headers();
  if (rawHeaders is! Map) {
    return headers;
  }

  rawHeaders.forEach((key, value) {
    final name = key?.toString();
    if (name == null || name.isEmpty) {
      return;
    }

    if (value is String) {
      headers.append(name, value);
      return;
    }

    if (value is List) {
      for (final item in value) {
        if (item is String) {
          headers.append(name, item);
        }
      }
    }
  });

  return headers;
}

Object? _bodyFromRaw(Object? rawBody) {
  return switch (rawBody) {
    null => null,
    String() => rawBody,
    Stream<List<int>>() => rawBody,
    List<int>() => rawBody,
    _ => null,
  };
}
