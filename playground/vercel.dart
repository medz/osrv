import 'package:osrv/esm.dart';

import 'server.dart' as playground;

void main() {
  defineFetchEntry(
    playground.server,
    runtime: const VercelFetchRuntime(),
  );
}
