import 'dart:async';

import 'package:ht/ht.dart';

import 'request.dart';

typedef Next = FutureOr<Response> Function(ServerRequest request);
typedef Middleware =
    FutureOr<Response> Function(ServerRequest request, Next next);
