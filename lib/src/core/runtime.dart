import 'capabilities.dart';

/// Represents a running server hosted by a concrete runtime family.
abstract interface class Runtime {
  /// Static identification for the runtime instance.
  RuntimeInfo get info;

  /// Capabilities exposed by the running runtime instance.
  RuntimeCapabilities get capabilities;

  /// Network address bound by the runtime when one exists.
  Uri? get url;

  /// Stops the runtime and resolves when shutdown completes.
  Future<void> close();

  /// Completes after the runtime has fully stopped.
  Future<void> get closed;
}

/// Identifies a runtime family and the role it is performing.
final class RuntimeInfo {
  /// Creates immutable metadata for a runtime instance.
  const RuntimeInfo({required this.name, required this.kind});

  /// Stable runtime family name such as `dart` or `node`.
  final String name;

  /// Runtime mode such as `server` or `entry`.
  final String kind;
}
