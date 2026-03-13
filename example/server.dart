import 'package:osrv/osrv.dart';

final server = Server(fetch: (request, context) => Response('Hello Osrv!'));
