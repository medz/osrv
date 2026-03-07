/// Thrown when a runtime configuration is structurally invalid.
final class RuntimeConfigurationError extends Error {
  /// Creates an error describing why runtime configuration validation failed.
  RuntimeConfigurationError(this.message);

  /// Human-readable validation failure details.
  final String message;

  @override
  String toString() => 'RuntimeConfigurationError: $message';
}

/// Thrown when a runtime fails during startup or binding.
final class RuntimeStartupError extends Error {
  /// Creates an error describing why runtime startup failed.
  RuntimeStartupError(this.message, [this.cause]);

  /// Human-readable startup failure details.
  final String message;

  /// The original error raised by the host, if one exists.
  final Object? cause;

  @override
  String toString() => 'RuntimeStartupError: $message';
}

/// Thrown when application code requires a capability the runtime does not expose.
final class UnsupportedRuntimeCapabilityError extends Error {
  /// Creates an error for an unavailable capability name.
  UnsupportedRuntimeCapabilityError(this.capability);

  /// The capability that was requested by application code.
  final String capability;

  @override
  String toString() =>
      'UnsupportedRuntimeCapabilityError: $capability is not supported.';
}
