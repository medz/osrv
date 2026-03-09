@JS()
library;

import 'dart:async';
import 'dart:js_interop';

/// Cloudflare Worker execution context for a single fetch event.
extension type CloudflareExecutionContext._(JSObject _) implements JSObject {
  /// Registers background work with the worker host.
  external void waitUntil(JSPromise task);

  /// Lets the worker continue through the platform exception pipeline.
  external void passThroughOnException();
}

/// Runs [task] with Cloudflare's background execution contract when available.
void cloudflareWaitUntil(
  CloudflareExecutionContext? context,
  Future<void> task,
) {
  if (context == null) {
    unawaited(
      task.catchError((Object error, StackTrace stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
      }),
    );
    return;
  }

  context.waitUntil(task.toJS);
}
