import 'package:ht/ht.dart';

import '../request.dart';
import '../types/index.dart';

Future<Response> runErrorHandler({
  required ServerRequest request,
  required Object error,
  required StackTrace stackTrace,
  required ErrorHandler? errorHandler,
}) async {
  if (error is Response) {
    return error;
  }

  if (errorHandler != null) {
    return await Future<Response>.value(
      errorHandler(request, error, stackTrace),
    );
  }

  return Response.text(
    'Internal Server Error',
    status: 500,
    headers: Headers({'content-type': 'text/plain; charset=utf-8'}),
  );
}
