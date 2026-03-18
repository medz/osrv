// ignore_for_file: public_member_api_docs

import 'dart:async';

final class ShutdownCoordinator {
  final _pendingTasks = <Future<void>>{};
  final _pendingRequests = <Future<void>>{};
  final _pendingConnections = <Future<void>>{};
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

  void trackConnection(Future<void> connection) {
    _pendingConnections.add(connection);
    connection.whenComplete(() {
      _pendingConnections.remove(connection);
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
    Object? firstError;
    StackTrace? firstStackTrace;

    try {
      await onStop();
    } catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }

    if (waitForRequests) {
      try {
        await _waitUntilDrained(_pendingRequests);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    try {
      await _waitUntilDrained(_pendingConnections);
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    try {
      await _waitUntilDrained(_pendingTasks);
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    if (firstError != null) {
      if (!_closedCompleter.isCompleted) {
        _closedCompleter.completeError(firstError, firstStackTrace);
      }
      return;
    }

    if (!_closedCompleter.isCompleted) {
      _closedCompleter.complete();
    }
  }

  static Future<void> _waitUntilDrained(Set<Future<void>> pending) async {
    while (pending.isNotEmpty) {
      await Future.wait(List<Future<void>>.of(pending));
    }
  }
}
