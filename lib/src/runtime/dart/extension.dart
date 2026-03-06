import 'dart:io';

import '../../core/extension.dart';

final class DartRuntimeExtension implements RuntimeExtension {
  const DartRuntimeExtension({
    required this.server,
    this.request,
    this.response,
  });

  final HttpServer server;
  final HttpRequest? request;
  final HttpResponse? response;
}
