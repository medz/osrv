import 'dart:async';

import 'extension.dart';
import 'http_host.dart';

typedef NodeHostRequestCallback =
    FutureOr<void> Function(NodeRuntimeExtension extension);

NodeHostRequestCallback createNodeHostRequestCallback(
  FutureOr<void> Function(
    NodeIncomingMessageHost request,
    NodeServerResponseHost response,
    NodeRuntimeExtension extension,
  )
  onRequest,
) {
  return (extension) async {
    final request = extension.request;
    final response = extension.response;
    if (request == null || response == null) {
      return;
    }

    await onRequest(request, response, extension);
  };
}
