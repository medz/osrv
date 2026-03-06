import 'dart:async';

final class VercelFunctionHelpersHost {
  const VercelFunctionHelpersHost();
}

final class VercelRuntimeCacheHost {
  const VercelRuntimeCacheHost();
}

const defaultVercelFunctionsOverrideName = '__osrv_vercel_functions__';

Future<VercelFunctionHelpersHost?> loadVercelFunctionHelpers() async {
  return null;
}

void resetVercelFunctionHelpersCache() {}

Future<void> vercelInvalidateByTag(
  VercelFunctionHelpersHost? helpers,
  Object tags,
) async {
  helpers;
  tags;
}

Future<void> vercelDangerouslyDeleteByTag(
  VercelFunctionHelpersHost? helpers,
  Object tags, {
  int? revalidationDeadlineSeconds,
}) async {
  helpers;
  tags;
  revalidationDeadlineSeconds;
}

Future<void> vercelInvalidateBySrcImage(
  VercelFunctionHelpersHost? helpers,
  String srcImage,
) async {
  helpers;
  srcImage;
}

Future<void> vercelDangerouslyDeleteBySrcImage(
  VercelFunctionHelpersHost? helpers,
  String srcImage, {
  int? revalidationDeadlineSeconds,
}) async {
  helpers;
  srcImage;
  revalidationDeadlineSeconds;
}

Future<void> vercelAddCacheTag(
  VercelFunctionHelpersHost? helpers,
  Object tags,
) async {
  helpers;
  tags;
}

VercelRuntimeCacheHost? vercelGetCache(
  VercelFunctionHelpersHost? helpers, {
  String? namespace,
  String? namespaceSeparator,
  String Function(String key)? keyHashFunction,
}) {
  helpers;
  namespace;
  namespaceSeparator;
  keyHashFunction;
  return null;
}

Future<Object?> vercelRuntimeCacheGet(
  VercelRuntimeCacheHost? cache,
  String key,
) async {
  cache;
  key;
  return null;
}

Future<void> vercelRuntimeCacheSet(
  VercelRuntimeCacheHost? cache,
  String key,
  Object? value, {
  String? name,
  List<String>? tags,
  int? ttl,
}) async {
  cache;
  key;
  value;
  name;
  tags;
  ttl;
}

Future<void> vercelRuntimeCacheDelete(
  VercelRuntimeCacheHost? cache,
  String key,
) async {
  cache;
  key;
}

Future<void> vercelRuntimeCacheExpireTag(
  VercelRuntimeCacheHost? cache,
  Object tags,
) async {
  cache;
  tags;
}

void vercelAttachDatabasePool(
  VercelFunctionHelpersHost? helpers,
  Object dbPool,
) {
  helpers;
  dbPool;
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
