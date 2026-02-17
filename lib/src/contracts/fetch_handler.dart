import 'dart:async';

import 'package:ht/ht.dart';

import 'request.dart';

typedef FetchHandler = FutureOr<Response> Function(ServerRequest request);
typedef ErrorHandler =
    FutureOr<Response> Function(ServerRequest request, Exception error);
