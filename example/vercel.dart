import 'package:osrv/esm.dart';

import 'server.dart' as example;

void main() {
  defineFetchEntry(example.server, runtime: FetchEntryRuntime.vercel);
}
