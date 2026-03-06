import 'dart:async';

final class ShutdownCoordinator {
  final _pendingTasks = <Future<void>>{};
  final _pendingRequests = <Future<void>>{};
  final _closedCompleter = Completer<void>();
  bool _stopTriggered = false;

  Future<void> get closed => _closedCompleter.future;

  void trackTask(Future<void> task) {
    _pendingTasks.add(task);
    task.whenComplete(() {
      _pendingTasks.remove(task);
    });
  }

  void trackRequest(Future<void> request) {
    _pendingRequests.add(request);
    request.whenComplete(() {
      _pendingRequests.remove(request);
    });
  }

  Future<void> stop({
    required Future<void> Function() onStop,
    bool waitForRequests = true,
  }) async {
    if (_stopTriggered) {
      return;
    }

    _stopTriggered = true;
    try {
      await onStop();

      if (waitForRequests) {
        await _waitUntilDrained(_pendingRequests);
      }

      await _waitUntilDrained(_pendingTasks);

      if (!_closedCompleter.isCompleted) {
        _closedCompleter.complete();
      }
    } catch (error, stackTrace) {
      if (!_closedCompleter.isCompleted) {
        _closedCompleter.completeError(error, stackTrace);
      }
    }
  }

  static Future<void> _waitUntilDrained(Set<Future<void>> pending) async {
    while (pending.isNotEmpty) {
      await Future.wait(List<Future<void>>.of(pending));
    }
  }
}
