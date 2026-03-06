import 'package:osrv/runtime/cloudflare.dart';

import 'server.dart' as playground;
import 'src/cloudflare_export_stub.dart'
    if (dart.library.js_interop) 'src/cloudflare_export_js.dart'
    as cloudflare_export;

final worker = cloudflareWorker(
  playground.server,
  const CloudflareRuntimeConfig(),
);

void main() {
  cloudflare_export.publishCloudflareWorker(worker);
}
