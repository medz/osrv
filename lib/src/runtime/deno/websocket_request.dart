// ignore_for_file: public_member_api_docs

import 'package:ht/ht.dart' show Headers, Response, ResponseInit;
import 'package:web/web.dart' as web;

import '../../core/websocket.dart';

final class DenoAcceptedWebSocketUpgrade {
  const DenoAcceptedWebSocketUpgrade({required this.handler, this.protocol});

  final WebSocketHandler handler;
  final String? protocol;
}

final class DenoWebSocketRequest implements WebSocketRequest {
  DenoWebSocketRequest(this._request)
    : _requestedProtocols = _parseRequestedProtocols(_request);

  final web.Request _request;
  final List<String> _requestedProtocols;
  DenoAcceptedWebSocketUpgrade? _acceptedUpgrade;
  Response? _acceptedResponse;

  @override
  bool get isUpgradeRequest {
    final upgrade = _request.headers.get('upgrade');
    final connection = _request.headers.get('connection');
    final connectionTokens = connection
        ?.split(',')
        .map((value) => value.trim().toLowerCase());
    return _request.method.toUpperCase() == 'GET' &&
        upgrade?.toLowerCase() == 'websocket' &&
        (connectionTokens?.contains('upgrade') ?? false);
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

    _acceptedUpgrade = DenoAcceptedWebSocketUpgrade(
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

  DenoAcceptedWebSocketUpgrade? takeAcceptedUpgrade(Response response) {
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
