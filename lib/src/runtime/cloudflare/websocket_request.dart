// ignore_for_file: public_member_api_docs

import 'package:ht/ht.dart' show Headers, Response, ResponseInit;
import 'package:web/web.dart' as web;

import '../../core/websocket.dart';

final class CloudflareAcceptedWebSocketUpgrade {
  const CloudflareAcceptedWebSocketUpgrade({
    required this.handler,
    this.protocol,
  });

  final WebSocketHandler handler;
  final String? protocol;
}

final class CloudflareWebSocketRequest implements WebSocketRequest {
  CloudflareWebSocketRequest(this._request)
    : _requestedProtocols = _parseRequestedProtocols(_request);

  final web.Request _request;
  final List<String> _requestedProtocols;
  CloudflareAcceptedWebSocketUpgrade? _acceptedUpgrade;
  Response? _acceptedResponse;

  @override
  bool get isUpgradeRequest {
    final upgrade = _request.headers.get('upgrade');
    final connection = _request.headers.get('connection');
    return upgrade?.toLowerCase() == 'websocket' &&
        connection?.toLowerCase().contains('upgrade') == true;
  }

  @override
  List<String> get requestedProtocols =>
      List<String>.unmodifiable(_requestedProtocols);

  @override
  Response accept(WebSocketHandler handler, {String? protocol}) {
    if (!isUpgradeRequest) {
      throw StateError(
        'Cannot accept a websocket for a non-upgrade HTTP request.',
      );
    }

    if (protocol != null && !_requestedProtocols.contains(protocol)) {
      throw ArgumentError.value(
        protocol,
        'protocol',
        'Selected websocket protocol must be one of the requested protocols.',
      );
    }

    if (_acceptedUpgrade != null) {
      throw StateError('A websocket upgrade has already been accepted.');
    }

    _acceptedUpgrade = CloudflareAcceptedWebSocketUpgrade(
      handler: handler,
      protocol: protocol,
    );
    final response = Response(
      null,
      ResponseInit(status: 101, headers: Headers({'upgrade': 'websocket'})),
    );
    _acceptedResponse = response;
    return response;
  }

  CloudflareAcceptedWebSocketUpgrade? takeAcceptedUpgrade(Response response) {
    final upgrade = _acceptedUpgrade;
    final acceptedResponse = _acceptedResponse;
    _acceptedUpgrade = null;
    _acceptedResponse = null;

    if (!identical(response, acceptedResponse)) {
      if (response.status == 101) {
        throw StateError(
          'HTTP 101 responses are reserved for context.webSocket.accept(...).',
        );
      }
      return null;
    }

    if (upgrade == null || acceptedResponse == null) {
      throw StateError(
        'HTTP 101 responses are reserved for context.webSocket.accept(...).',
      );
    }

    return upgrade;
  }

  bool hasAcceptedUpgrade(Response response) {
    return _acceptedUpgrade != null && identical(response, _acceptedResponse);
  }
}

List<String> _parseRequestedProtocols(web.Request request) {
  final header = request.headers.get('sec-websocket-protocol');
  if (header == null || header.isEmpty) {
    return const <String>[];
  }

  return header
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}
