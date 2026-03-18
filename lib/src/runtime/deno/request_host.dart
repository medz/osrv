// ignore_for_file: public_member_api_docs

@JS()
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

extension type DenoRequestHost._(JSObject _) implements JSObject {}

DenoRequestHost denoRequestHostFromWebRequest(web.Request request) {
  return DenoRequestHost._(request as JSObject);
}
