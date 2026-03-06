import 'package:ht/ht.dart' show Response;
import 'package:web/web.dart' as web;

import '../_internal/js/web_response_bridge.dart';

web.Response vercelResponseFromHtResponse(
  Response source,
) {
  return webResponseFromHtResponse(source);
}
