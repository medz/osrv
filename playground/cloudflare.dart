import 'package:osrv/runtime/cloudflare.dart';

import 'server.dart' as playground;

final worker = cloudflareWorker(
  playground.server,
  const CloudflareRuntimeConfig(),
);
