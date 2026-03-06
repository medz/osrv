import 'package:ht/ht.dart' show Request;
import 'package:web/web.dart' as web;

import '../_internal/js/web_request_bridge.dart';

Request cloudflareRequestToHtRequest(
  web.Request request,
) {
  return htRequestFromWebRequest(request);
}
