import 'package:ht/ht.dart';

import 'request.dart';
import 'server_options.dart';

class Runtime {
  const Runtime({required this.name});

  final String name;
}

abstract interface class Server {
  Runtime get runtime;
  ServerOptions get options;
  Uri get url;
  String get addr;
  int get port;

  Future<Response> fetch(ServerRequest request);

  // When manual is `true`
  Future<Server> serve();
  Future<Server> ready();
  Future<void> close([bool? closeActiveConnections]);
}
