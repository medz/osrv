import 'dart:async';

import 'host.dart';

/// Wraps the helper APIs exposed by `@vercel/functions`.
final class VercelFunctions {
  /// Creates a Vercel helper facade for the current request.
  const VercelFunctions._(this._helpers, {Object? request})
    : _request = request;

  final VercelFunctionHelpersHost? _helpers;
  final Object? _request;

  /// Schedules background work via Vercel's `waitUntil` integration.
  void waitUntil(Future<void> task) {
    vercelWaitUntil(_helpers, task);
  }

  /// Returns environment bindings exposed by the host, when available.
  Object? get env => vercelGetEnv(_helpers);

  /// Returns Vercel geolocation data for the current request, when available.
  Object? get geolocation {
    final request = _request;
    if (request == null) {
      return null;
    }

    return vercelGeolocation(_helpers, request);
  }

  /// Returns the client IP address for the current request, when available.
  String? get ipAddress {
    final request = _request;
    if (request == null) {
      return null;
    }

    return vercelIpAddress(_helpers, request);
  }

  /// Invalidates one or more cache tags.
  Future<void> invalidateByTag(
    String tag, [
    List<String> additionalTags = const [],
  ]) {
    return vercelInvalidateByTag(_helpers, _mergeTagInput(tag, additionalTags));
  }

  /// Deletes one or more cache tags immediately.
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

  /// Invalidates a cached source image.
  Future<void> invalidateBySrcImage(String srcImage) {
    return vercelInvalidateBySrcImage(_helpers, srcImage);
  }

  /// Deletes a cached source image immediately.
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

  /// Adds one or more cache tags to the current execution context.
  Future<void> addCacheTag(
    String tag, [
    List<String> additionalTags = const [],
  ]) {
    return vercelAddCacheTag(_helpers, _mergeTagInput(tag, additionalTags));
  }

  /// Returns a namespaced Vercel runtime cache facade.
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

  /// Registers a database pool so the host can manage its lifecycle.
  void attachDatabasePool(Object dbPool) {
    vercelAttachDatabasePool(_helpers, dbPool);
  }
}

/// Wraps a Vercel runtime cache namespace.
final class VercelRuntimeCache {
  /// Creates a runtime cache facade.
  const VercelRuntimeCache._(this._cache);

  final VercelRuntimeCacheHost? _cache;

  /// Retrieves a cached value by key.
  Future<Object?> get(String key) => vercelRuntimeCacheGet(_cache, key);

  /// Stores a value under [key].
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

  /// Deletes a cached value by key.
  Future<void> delete(String key) => vercelRuntimeCacheDelete(_cache, key);

  /// Expires one or more tags within this cache namespace.
  Future<void> expireTag(String tag, [List<String> additionalTags = const []]) {
    return vercelRuntimeCacheExpireTag(
      _cache,
      _mergeTagInput(tag, additionalTags),
    );
  }
}

/// Creates the request-bound Vercel helper facade used by runtime adapters.
VercelFunctions createVercelFunctions(
  VercelFunctionHelpersHost? helpers,
  Object? request,
) {
  return VercelFunctions._(helpers, request: request);
}

Object _mergeTagInput(String tag, List<String> additionalTags) {
  if (additionalTags.isEmpty) {
    return tag;
  }

  return <String>[tag, ...additionalTags];
}
