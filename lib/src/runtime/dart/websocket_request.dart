// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:ht/ht.dart' show Response, ResponseInit;

import '../../core/websocket.dart';

final class DartAcceptedWebSocketUpgrade {
  const DartAcceptedWebSocketUpgrade({required this.handler, this.protocol});

  final WebSocketHandler handler;
  final String? protocol;
}

final class DartWebSocketRequest implements WebSocketRequest {
  DartWebSocketRequest(this._request)
    : _requestedProtocols = _parseRequestedProtocols(_request);

  final HttpRequest _request;
  final List<String> _requestedProtocols;
  DartAcceptedWebSocketUpgrade? _acceptedUpgrade;

  @override
  bool get isUpgradeRequest => WebSocketTransformer.isUpgradeRequest(_request);

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

    _acceptedUpgrade = DartAcceptedWebSocketUpgrade(
      handler: handler,
      protocol: protocol,
    );

    return Response(
      null,
      const ResponseInit(status: HttpStatus.switchingProtocols),
    );
  }

  DartAcceptedWebSocketUpgrade? takeAcceptedUpgrade(Response response) {
    final upgrade = _acceptedUpgrade;
    _acceptedUpgrade = null;

    if (response.status != HttpStatus.switchingProtocols) {
      return null;
    }

    if (upgrade == null) {
      throw StateError(
        'HTTP 101 responses are reserved for context.webSocket.accept(...).',
      );
    }

    return upgrade;
  }

  bool hasAcceptedUpgrade(Response response) {
    return response.status == HttpStatus.switchingProtocols &&
        _acceptedUpgrade != null;
  }
}

List<String> _parseRequestedProtocols(HttpRequest request) {
  final values = request.headers['sec-websocket-protocol'];
  if (values == null || values.isEmpty) {
    return const <String>[];
  }

  return values
      .expand((value) => value.split(','))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}
