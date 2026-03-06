import 'dart:async';

import 'host.dart';

final class VercelFunctions {
  const VercelFunctions._(
    this._helpers, {
    Object? request,
  }) : _request = request;

  final VercelFunctionHelpersHost? _helpers;
  final Object? _request;

  void waitUntil(Future<void> task) {
    vercelWaitUntil(_helpers, task);
  }

  Object? get env => vercelGetEnv(_helpers);

  Object? get geolocation {
    final request = _request;
    if (request == null) {
      return null;
    }

    return vercelGeolocation(_helpers, request);
  }

  String? get ipAddress {
    final request = _request;
    if (request == null) {
      return null;
    }

    return vercelIpAddress(_helpers, request);
  }

  Future<void> invalidateByTag(
    String tag, [
    List<String> additionalTags = const [],
  ]) {
    return vercelInvalidateByTag(_helpers, _mergeTagInput(tag, additionalTags));
  }

  Future<void> dangerouslyDeleteByTag(
    String tag, {
    List<String> additionalTags = const [],
    int? revalidationDeadlineSeconds,
  }) {
    return vercelDangerouslyDeleteByTag(
      _helpers,
      _mergeTagInput(tag, additionalTags),
      revalidationDeadlineSeconds: revalidationDeadlineSeconds,
    );
  }

  Future<void> invalidateBySrcImage(String srcImage) {
    return vercelInvalidateBySrcImage(_helpers, srcImage);
  }

  Future<void> dangerouslyDeleteBySrcImage(
    String srcImage, {
    int? revalidationDeadlineSeconds,
  }) {
    return vercelDangerouslyDeleteBySrcImage(
      _helpers,
      srcImage,
      revalidationDeadlineSeconds: revalidationDeadlineSeconds,
    );
  }

  Future<void> addCacheTag(
    String tag, [
    List<String> additionalTags = const [],
  ]) {
    return vercelAddCacheTag(_helpers, _mergeTagInput(tag, additionalTags));
  }

  VercelRuntimeCache getCache({
    String? namespace,
    String? namespaceSeparator,
    String Function(String key)? keyHashFunction,
  }) {
    return VercelRuntimeCache._(
      vercelGetCache(
        _helpers,
        namespace: namespace,
        namespaceSeparator: namespaceSeparator,
        keyHashFunction: keyHashFunction,
      ),
    );
  }

  void attachDatabasePool(Object dbPool) {
    vercelAttachDatabasePool(_helpers, dbPool);
  }
}

final class VercelRuntimeCache {
  const VercelRuntimeCache._(this._cache);

  final VercelRuntimeCacheHost? _cache;

  Future<Object?> get(String key) => vercelRuntimeCacheGet(_cache, key);

  Future<void> set(
    String key,
    Object? value, {
    String? name,
    List<String>? tags,
    int? ttl,
  }) {
    return vercelRuntimeCacheSet(
      _cache,
      key,
      value,
      name: name,
      tags: tags,
      ttl: ttl,
    );
  }

  Future<void> delete(String key) => vercelRuntimeCacheDelete(_cache, key);

  Future<void> expireTag(
    String tag, [
    List<String> additionalTags = const [],
  ]) {
    return vercelRuntimeCacheExpireTag(
      _cache,
      _mergeTagInput(tag, additionalTags),
    );
  }
}

VercelFunctions createVercelFunctions(
  VercelFunctionHelpersHost? helpers,
  Object? request,
) {
  return VercelFunctions._(
    helpers,
    request: request,
  );
}

Object _mergeTagInput(String tag, List<String> additionalTags) {
  if (additionalTags.isEmpty) {
    return tag;
  }

  return <String>[tag, ...additionalTags];
}
