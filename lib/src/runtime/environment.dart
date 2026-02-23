import 'environment_stub.dart'
    if (dart.library.io) 'environment_io.dart'
    if (dart.library.js_interop) 'environment_js.dart'
    as impl;

Map<String, String> readRuntimeEnvironment() => impl.readRuntimeEnvironment();
