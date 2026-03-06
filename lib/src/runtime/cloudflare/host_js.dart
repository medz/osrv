@JS()
library;

import 'dart:async';
import 'dart:js_interop';

extension type CloudflareExecutionContext._(JSObject _) implements JSObject {
  external void waitUntil(JSPromise task);
  external void passThroughOnException();
}

void cloudflareWaitUntil(
  CloudflareExecutionContext? context,
  Future<void> task,
) {
  if (context == null) {
    unawaited(task);
    return;
  }

  context.waitUntil(task.toJS);
}
