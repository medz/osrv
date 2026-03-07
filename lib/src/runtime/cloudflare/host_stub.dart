import 'dart:async';

/// Test stub for Cloudflare's execution context.
final class CloudflareExecutionContext {
  /// Creates an in-memory execution context stub.
  CloudflareExecutionContext();

  /// Tasks registered through [waitUntil] during tests.
  final List<Future<void>> tasks = <Future<void>>[];

  /// Stores a task for later inspection.
  void waitUntil(Future<void> task) {
    tasks.add(task);
  }

  /// No-op stub for Cloudflare's exception pass-through hook.
  void passThroughOnException() {}
}

/// Runs [task] with Cloudflare's background execution contract when available.
void cloudflareWaitUntil(
  CloudflareExecutionContext? context,
  Future<void> task,
) {
  if (context == null) {
    unawaited(task);
    return;
  }

  context.waitUntil(task);
}
