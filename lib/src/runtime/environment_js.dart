import 'dart:js_interop';

@JS('globalThis')
external JSObject get _globalThisObject;

extension type _GlobalThis._(JSObject _) implements JSObject {
  external JSObject? get process;

  // ignore: non_constant_identifier_names
  external JSObject? get Deno;
}

extension type _NodeProcess._(JSObject _) implements JSObject {
  external JSObject? get env;
}

extension type _DenoGlobal._(JSObject _) implements JSObject {
  external _DenoEnvironment? get env;
}

extension type _DenoEnvironment._(JSObject _) implements JSObject {
  external JSObject toObject();
}

@JS('Object')
extension type _ObjectStatic._(JSAny _) {
  external static JSArray<JSArray<JSAny?>> entries(JSObject value);
}

Map<String, String> readRuntimeEnvironment() {
  final environment = <String, String>{};
  final global = _GlobalThis._(_globalThisObject);

  final process = global.process;
  if (process != null) {
    final processEnv = _NodeProcess._(process).env;
    if (processEnv != null) {
      _appendEntries(environment, processEnv);
    }
  }

  final deno = global.Deno;
  if (deno != null) {
    final denoEnv = _DenoGlobal._(deno).env;
    if (denoEnv != null) {
      _appendEntries(environment, denoEnv.toObject());
    }
  }

  return environment;
}

void _appendEntries(Map<String, String> output, JSObject source) {
  for (final entry in _ObjectStatic.entries(source).toDart) {
    final values = entry.toDart;
    if (values.length < 2) {
      continue;
    }

    final keyAny = values[0];
    final valueAny = values[1];
    if (keyAny == null ||
        valueAny == null ||
        !keyAny.isA<JSString>() ||
        !valueAny.isA<JSString>()) {
      continue;
    }

    final key = (keyAny as JSString).toDart;
    if (key.isEmpty) {
      continue;
    }

    output[key] = (valueAny as JSString).toDart;
  }
}
