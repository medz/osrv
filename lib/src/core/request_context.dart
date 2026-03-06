import 'dart:async';

import 'capabilities.dart';
import 'extension.dart';
import 'runtime.dart';

abstract interface class RequestContext {
  RuntimeInfo get runtime;
  RuntimeCapabilities get capabilities;

  void waitUntil(Future<void> task);

  T? extension<T extends RuntimeExtension>();
}
