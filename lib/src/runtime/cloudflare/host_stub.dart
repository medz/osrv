import 'dart:async';

final class CloudflareExecutionContext {
  CloudflareExecutionContext();

  final List<Future<void>> tasks = <Future<void>>[];

  void waitUntil(Future<void> task) {
    tasks.add(task);
  }

  void passThroughOnException() {}
}

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
