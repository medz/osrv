// ignore_for_file: public_member_api_docs

@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

extension type VercelFunctionHelpersHost._(JSObject _) implements JSObject {}
extension type VercelRuntimeCacheHost._(JSObject _) implements JSObject {}

const defaultVercelFunctionsOverrideName = '__osrv_vercel_functions__';
Future<VercelFunctionHelpersHost?>? _helpersOperation;

Future<VercelFunctionHelpersHost?> loadVercelFunctionHelpers() {
  final override = globalContext.getProperty<JSObject?>(
    defaultVercelFunctionsOverrideName.toJS,
  );
  if (override != null) {
    return Future.value(VercelFunctionHelpersHost._(override));
  }

  final existing = _helpersOperation;
  if (existing != null) {
    return existing;
  }

  final operation = () async {
    final module = await importModule('@vercel/functions'.toJS).toDart;
    return VercelFunctionHelpersHost._(module);
  }();
  _helpersOperation = operation;
  return operation;
}

void resetVercelFunctionHelpersCache() {
  _helpersOperation = null;
}

Future<void> vercelInvalidateByTag(
  VercelFunctionHelpersHost? helpers,
  Object tags,
) {
  return _vercelInvokeVoid(helpers, 'invalidateByTag', [
    _toJsTagArgument(tags),
  ]);
}

Future<void> vercelDangerouslyDeleteByTag(
  VercelFunctionHelpersHost? helpers,
  Object tags, {
  int? revalidationDeadlineSeconds,
}) {
  final arguments = <JSAny?>[_toJsTagArgument(tags)];
  if (revalidationDeadlineSeconds != null) {
    arguments.add(
      JSObject()..setProperty(
        'revalidationDeadlineSeconds'.toJS,
        revalidationDeadlineSeconds.toJS,
      ),
    );
  }

  return _vercelInvokeVoid(helpers, 'dangerouslyDeleteByTag', arguments);
}

Future<void> vercelInvalidateBySrcImage(
  VercelFunctionHelpersHost? helpers,
  String srcImage,
) {
  return _vercelInvokeVoid(helpers, 'invalidateBySrcImage', [srcImage.toJS]);
}

Future<void> vercelDangerouslyDeleteBySrcImage(
  VercelFunctionHelpersHost? helpers,
  String srcImage, {
  int? revalidationDeadlineSeconds,
}) {
  final arguments = <JSAny?>[srcImage.toJS];
  if (revalidationDeadlineSeconds != null) {
    arguments.add(
      JSObject()..setProperty(
        'revalidationDeadlineSeconds'.toJS,
        revalidationDeadlineSeconds.toJS,
      ),
    );
  }

  return _vercelInvokeVoid(helpers, 'dangerouslyDeleteBySrcImage', arguments);
}

Future<void> vercelAddCacheTag(
  VercelFunctionHelpersHost? helpers,
  Object tags,
) {
  return _vercelInvokeVoid(helpers, 'addCacheTag', [_toJsTagArgument(tags)]);
}

VercelRuntimeCacheHost? vercelGetCache(
  VercelFunctionHelpersHost? helpers, {
  String? namespace,
  String? namespaceSeparator,
  String Function(String key)? keyHashFunction,
}) {
  final getter = helpers?.getProperty<JSFunction?>('getCache'.toJS);
  if (getter == null) {
    return null;
  }

  final options = JSObject();
  if (namespace != null) {
    options.setProperty('namespace'.toJS, namespace.toJS);
  }
  if (namespaceSeparator != null) {
    options.setProperty('namespaceSeparator'.toJS, namespaceSeparator.toJS);
  }
  if (keyHashFunction != null) {
    options.setProperty(
      'keyHashFunction'.toJS,
      ((String key) => keyHashFunction(key)).toJS,
    );
  }

  final cache = getter.callAsFunction(
    helpers,
    namespace == null && namespaceSeparator == null && keyHashFunction == null
        ? null
        : options,
  );
  if (cache == null) {
    return null;
  }

  return VercelRuntimeCacheHost._(cache as JSObject);
}

Future<Object?> vercelRuntimeCacheGet(
  VercelRuntimeCacheHost? cache,
  String key,
) async {
  if (cache == null) {
    return null;
  }

  final getter = cache.getProperty<JSFunction?>('get'.toJS);
  if (getter == null) {
    return null;
  }

  final result = getter.callAsFunction(cache, key.toJS);
  if (result == null) {
    return null;
  }

  return (await (result as JSPromise<JSAny?>).toDart)?.dartify();
}

Future<void> vercelRuntimeCacheSet(
  VercelRuntimeCacheHost? cache,
  String key,
  Object? value, {
  String? name,
  List<String>? tags,
  int? ttl,
}) async {
  if (cache == null) {
    return;
  }

  final setter = cache.getProperty<JSFunction?>('set'.toJS);
  if (setter == null) {
    return;
  }

  final args = <JSAny?>[key.toJS, value.jsify()];

  if (name != null || tags != null || ttl != null) {
    final options = JSObject();
    if (name != null) {
      options.setProperty('name'.toJS, name.toJS);
    }
    if (tags != null) {
      options.setProperty('tags'.toJS, tags.jsify()!);
    }
    if (ttl != null) {
      options.setProperty('ttl'.toJS, ttl.toJS);
    }
    args.add(options);
  }

  final result = setter.callMethodVarArgs<JSAny?>('call'.toJS, [
    cache,
    ...args,
  ]);
  if (result != null) {
    await (result as JSPromise<JSAny?>).toDart;
  }
}

Future<void> vercelRuntimeCacheDelete(
  VercelRuntimeCacheHost? cache,
  String key,
) async {
  if (cache == null) {
    return;
  }

  final deleter = cache.getProperty<JSFunction?>('delete'.toJS);
  if (deleter == null) {
    return;
  }

  final result = deleter.callAsFunction(cache, key.toJS);
  if (result != null) {
    await (result as JSPromise<JSAny?>).toDart;
  }
}

Future<void> vercelRuntimeCacheExpireTag(
  VercelRuntimeCacheHost? cache,
  Object tags,
) async {
  if (cache == null) {
    return;
  }

  final expirer = cache.getProperty<JSFunction?>('expireTag'.toJS);
  if (expirer == null) {
    return;
  }

  final result = expirer.callAsFunction(cache, _toJsTagArgument(tags));
  if (result != null) {
    await (result as JSPromise<JSAny?>).toDart;
  }
}

void vercelAttachDatabasePool(
  VercelFunctionHelpersHost? helpers,
  Object dbPool,
) {
  final attach = helpers?.getProperty<JSFunction?>('attachDatabasePool'.toJS);
  if (attach == null) {
    return;
  }

  attach.callAsFunction(helpers, dbPool.jsify());
}

void vercelWaitUntil(VercelFunctionHelpersHost? helpers, Future<void> task) {
  final waitUntil = helpers?.getProperty<JSFunction?>('waitUntil'.toJS);
  if (waitUntil == null) {
    unawaited(task);
    return;
  }

  waitUntil.callAsFunction(helpers, task.toJS);
}

Object? vercelGetEnv(VercelFunctionHelpersHost? helpers) {
  final getter = helpers?.getProperty<JSFunction?>('getEnv'.toJS);
  if (getter == null) {
    return null;
  }

  return getter.callAsFunction(helpers)?.dartify();
}

Object? vercelGeolocation(VercelFunctionHelpersHost? helpers, Object request) {
  final getter = helpers?.getProperty<JSFunction?>('geolocation'.toJS);
  if (getter == null) {
    return null;
  }

  return getter.callAsFunction(helpers, request as JSAny?)?.dartify();
}

String? vercelIpAddress(VercelFunctionHelpersHost? helpers, Object request) {
  final getter = helpers?.getProperty<JSFunction?>('ipAddress'.toJS);
  if (getter == null) {
    return null;
  }

  final value = getter.callAsFunction(helpers, request as JSAny?);
  if (value == null) {
    return null;
  }

  return (value as JSString).toDart;
}

Future<void> _vercelInvokeVoid(
  VercelFunctionHelpersHost? helpers,
  String name,
  List<JSAny?> arguments,
) async {
  final method = helpers?.getProperty<JSFunction?>(name.toJS);
  if (method == null) {
    return;
  }

  final result = method.callMethodVarArgs<JSAny?>('call'.toJS, [
    helpers,
    ...arguments,
  ]);
  if (result != null) {
    await (result as JSPromise<JSAny?>).toDart;
  }
}

JSAny _toJsTagArgument(Object tags) {
  if (tags is String) {
    return tags.toJS;
  }

  if (tags is List<String>) {
    return tags.jsify()!;
  }

  throw ArgumentError.value(
    tags,
    'tags',
    'Expected a String or List<String> tag input.',
  );
}
