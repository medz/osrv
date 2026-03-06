import 'capabilities.dart';

abstract interface class Runtime {
  RuntimeInfo get info;
  RuntimeCapabilities get capabilities;
  Uri? get url;

  Future<void> close();
  Future<void> get closed;
}

final class RuntimeInfo {
  const RuntimeInfo({required this.name, required this.kind});

  final String name;
  final String kind;
}
