import 'dart:io';

import '../_internal/server/runtime_handle.dart';

final class DartRuntime extends ServerRuntimeHandle {
  DartRuntime({
    required HttpServer server,
    required super.info,
    required super.capabilities,
    required super.closed,
    required this.host,
    required this.port,
    required void Function() onClose,
  }) : super(
         url: Uri(
           scheme: 'http',
           host: host,
           port: port,
         ),
         onClose: () async {
           onClose();
           await server.close();
           await closed;
         },
       );
  final String host;
  final int port;
}
