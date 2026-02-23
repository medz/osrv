import 'environment_stub.dart'
    if (dart.library.io) 'environment_io.dart'
    as impl;

Map<String, String> readRuntimeEnvironment() => impl.readRuntimeEnvironment();
