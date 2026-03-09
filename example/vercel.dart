import 'package:osrv/runtime/vercel.dart';

import 'server.dart' as example;

void main() {
  defineFetchExport(example.server);
}
