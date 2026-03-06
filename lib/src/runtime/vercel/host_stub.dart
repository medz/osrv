import 'dart:async';

final class VercelFunctionHelpersHost {
  const VercelFunctionHelpersHost();
}

void vercelWaitUntil(
  VercelFunctionHelpersHost? helpers,
  Future<void> task,
) {
  helpers;
  unawaited(task);
}

Object? vercelGetEnv(VercelFunctionHelpersHost? helpers) {
  helpers;
  return null;
}

Object? vercelGeolocation(
  VercelFunctionHelpersHost? helpers,
  Object request,
) {
  helpers;
  request;
  return null;
}

String? vercelIpAddress(
  VercelFunctionHelpersHost? helpers,
  Object request,
) {
  helpers;
  request;
  return null;
}
