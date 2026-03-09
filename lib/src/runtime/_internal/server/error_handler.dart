// ignore_for_file: public_member_api_docs

import 'package:ht/ht.dart' show Response;

import '../../../core/request_context.dart';
import '../../../core/server.dart';

Future<Response> handleServerError({
  required Server server,
  required Object error,
  required StackTrace stackTrace,
  required ServerLifecycleContext context,
  int defaultStatus = 500,
}) async {
  if (server.onError != null) {
    final response = await server.onError!(error, stackTrace, context);
    if (response != null) {
      return response;
    }
  }

  return Response.text('Internal Server Error', status: defaultStatus);
}
