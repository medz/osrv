// ignore_for_file: public_member_api_docs

@JS()
library;

import 'dart:js_interop';
import 'package:web/web.dart' as web;

extension type BunRequestHost._(JSObject _) implements JSObject {}

BunRequestHost bunRequestHostFromWebRequest(web.Request request) {
  return BunRequestHost._(request as JSObject);
}
