import 'dart:async';

final class VercelFunctionHelpersHost {
  const VercelFunctionHelpersHost();
}

const defaultVercelFunctionsOverrideName = '__osrv_vercel_functions__';

Future<VercelFunctionHelpersHost?> loadVercelFunctionHelpers() async {
  return null;
}

void resetVercelFunctionHelpersCache() {}

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
