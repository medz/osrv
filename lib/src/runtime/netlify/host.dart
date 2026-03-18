@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Netlify Functions context for a single request invocation.
extension type NetlifyContext(JSObject _) implements JSObject {
  /// Netlify account metadata for the current invocation, when available.
  external JSObject? get account;

  /// Netlify cookie helpers for the current invocation, when available.
  external JSObject? get cookies;

  /// Netlify deploy metadata for the current invocation, when available.
  external JSObject? get deploy;

  /// Netlify geolocation metadata for the current invocation, when available.
  external JSObject? get geo;

  /// The resolved client IP address when the host provides it.
  external String? get ip;

  /// Netlify route params for the current invocation, when available.
  Object? get params => _params?.dartify();

  /// Netlify's request ID for the current invocation, when available.
  external String? get requestId;

  /// Netlify server metadata for the current invocation, when available.
  external JSObject? get server;

  /// Netlify site metadata for the current invocation, when available.
  external JSObject? get site;

  /// Registers background work with the function host.
  external void waitUntil(JSPromise task);

  @JS('params')
  external JSAny? get _params;
}

/// Runs [task] with Netlify's background execution contract when available.
void netlifyWaitUntil(NetlifyContext? context, Future<void> task) {
  if (context == null) {
    _forwardUnhandledTask(task);
    return;
  }

  if (!netlifySupportsBackgroundTask(context)) {
    _forwardUnhandledTask(task);
    return;
  }

  context.waitUntil(task.toJS);
}

/// Returns whether the current invocation supports `waitUntil(...)`.
bool netlifySupportsBackgroundTask(NetlifyContext? context) {
  if (context == null) {
    return false;
  }

  return (context as JSObject).getProperty<JSFunction?>('waitUntil'.toJS) !=
      null;
}

void _forwardUnhandledTask(Future<void> task) {
  unawaited(
    task.catchError((Object error, StackTrace stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }),
  );
}
