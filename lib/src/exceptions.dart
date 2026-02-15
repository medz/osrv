final class RequestLimitExceeded implements Exception {
  const RequestLimitExceeded({
    required this.maxBytes,
    required this.actualBytes,
  });

  final int maxBytes;
  final int actualBytes;

  @override
  String toString() {
    return 'RequestLimitExceeded(maxBytes: $maxBytes, actualBytes: $actualBytes)';
  }
}
