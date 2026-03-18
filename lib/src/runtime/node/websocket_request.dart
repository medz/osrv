// ignore_for_file: public_member_api_docs

import 'package:ht/ht.dart' show Response, ResponseInit;

import '../../core/websocket.dart';

final class NodeAcceptedWebSocketUpgrade {
  const NodeAcceptedWebSocketUpgrade({required this.handler, this.protocol});

  final WebSocketHandler handler;
  final String? protocol;
}

final class NodeWebSocketRequest implements WebSocketRequest {
  NodeWebSocketRequest({
    required this.isUpgradeRequest,
    required List<String> requestedProtocols,
  }) : _requestedProtocols = List<String>.unmodifiable(requestedProtocols);

  @override
  final bool isUpgradeRequest;

  final List<String> _requestedProtocols;
  NodeAcceptedWebSocketUpgrade? _acceptedUpgrade;
  Response? _acceptedResponse;

  @override
  List<String> get requestedProtocols => _requestedProtocols;

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

    _acceptedUpgrade = NodeAcceptedWebSocketUpgrade(
      handler: handler,
      protocol: protocol,
    );
    final response = Response(null, const ResponseInit(status: 101));
    _acceptedResponse = response;
    return response;
  }

  NodeAcceptedWebSocketUpgrade? takeAcceptedUpgrade(Response response) {
    final upgrade = _acceptedUpgrade;
    final acceptedResponse = _acceptedResponse;

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

    _acceptedUpgrade = null;
    _acceptedResponse = null;

    return upgrade;
  }

  bool hasAcceptedUpgrade(Response response) {
    return identical(response, _acceptedResponse);
  }
}
