@JS()
library;

import 'dart:js_interop';

@JS('globalThis')
external JSObject get _globalThis;

@JS('Bun')
external JSObject? get _bunGlobal;

extension type BunHostObject._(JSObject _) implements JSObject {}

extension type BunGlobal._(JSObject _) implements JSObject {
  external JSString? get version;
  @JS('serve')
  external JSFunction? get serve;
}

BunHostObject? get globalThis => BunHostObject._(_globalThis);

BunGlobal? get bunGlobal {
  final value = _bunGlobal;
  if (value == null) {
    return null;
  }

  return BunGlobal._(value);
}

String? bunVersion(BunGlobal bun) => bun.version?.toDart;

bool bunHasServe(BunGlobal bun) => bun.serve != null;
