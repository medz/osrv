import 'dart:async';

import 'package:ht/ht.dart';

import '../request.dart';

typedef FetchHandler = FutureOr<Response> Function(ServerRequest request);
typedef ErrorHandler =
    FutureOr<Response> Function(
      ServerRequest request,
      Object error,
      StackTrace stackTrace,
    );
typedef Next = Future<Response> Function(ServerRequest request);
typedef Middleware =
    FutureOr<Response> Function(ServerRequest request, Next next);
