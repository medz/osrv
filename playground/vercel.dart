import 'package:osrv/runtime/vercel.dart';

import 'server.dart' as playground;

void main() {
  defineVercelFetch(playground.server);
}
