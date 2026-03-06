final class RuntimeConfigurationError extends Error {
  RuntimeConfigurationError(this.message);

  final String message;

  @override
  String toString() => 'RuntimeConfigurationError: $message';
}

final class RuntimeStartupError extends Error {
  RuntimeStartupError(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'RuntimeStartupError: $message';
}

final class UnsupportedRuntimeCapabilityError extends Error {
  UnsupportedRuntimeCapabilityError(this.capability);

  final String capability;

  @override
  String toString() =>
      'UnsupportedRuntimeCapabilityError: $capability is not supported.';
}
