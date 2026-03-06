@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

extension type VercelFunctionHelpersHost._(JSObject _) implements JSObject {}

void vercelWaitUntil(
  VercelFunctionHelpersHost? helpers,
  Future<void> task,
) {
  final waitUntil = helpers?.getProperty<JSFunction?>('waitUntil'.toJS);
  if (waitUntil == null) {
    unawaited(task);
    return;
  }

  waitUntil.callAsFunction(helpers, task.toJS);
}

Object? vercelGetEnv(VercelFunctionHelpersHost? helpers) {
  final getter = helpers?.getProperty<JSFunction?>('getEnv'.toJS);
  if (getter == null) {
    return null;
  }

  return getter.callAsFunction(helpers)?.dartify();
}

Object? vercelGeolocation(
  VercelFunctionHelpersHost? helpers,
  web.Request request,
) {
  final getter = helpers?.getProperty<JSFunction?>('geolocation'.toJS);
  if (getter == null) {
    return null;
  }

  return getter.callAsFunction(helpers, request as JSAny?)?.dartify();
}

String? vercelIpAddress(
  VercelFunctionHelpersHost? helpers,
  web.Request request,
) {
  final getter = helpers?.getProperty<JSFunction?>('ipAddress'.toJS);
  if (getter == null) {
    return null;
  }

  final value = getter.callAsFunction(helpers, request as JSAny?);
  if (value == null) {
    return null;
  }

  return (value as JSString).toDart;
}
