import 'dart:async';

import 'package:ht/ht.dart';

import 'request_context.dart';

typedef WaitUntil = void Function<T>(FutureOr<T> Function() run);

abstract interface class ServerRequest implements Request {
  RequestContext get context;
  String get ip;
  WaitUntil get waitUntil;
}
