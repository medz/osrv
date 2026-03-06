import 'extension.dart';
import 'http_host.dart';

typedef NodeHostRequestCallback = void Function(NodeRuntimeExtension extension);

NodeHostRequestCallback createNodeHostRequestCallback(
  void Function(
    NodeIncomingMessageHost request,
    NodeServerResponseHost response,
    NodeRuntimeExtension extension,
  )
  onRequest,
) {
  return (extension) {
    final request = extension.request;
    final response = extension.response;
    if (request == null || response == null) {
      return;
    }

    onRequest(request, response, extension);
  };
}
