import 'options.dart';
import 'runtime.dart';

abstract interface class ServerHandle {
  Runtime get runtime;
  ServerOptions get options;
  Uri get url;
  String get addr;
  int get port;
}
