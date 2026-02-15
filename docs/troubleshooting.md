# Troubleshooting

## `bun run dist/js/bun/index.mjs` fails

Check direct-deploy prerequisites:

1. `dist/js/core/<entry>.js` exists (`dart run osrv build`).
2. Your Dart entry calls `await server.serve()` so `globalThis.__osrv_main__` is registered.
3. Entry code intended for JS targets should avoid `dart:io` APIs.

## `globalThis.__osrv_main__ is not set`

The built adapter started before Dart core registered the handler, or your entry
did not call `server.serve()`.

Fix:

```dart
import 'package:osrv/osrv.dart';

Future<void> main() async {
  final server = Server(fetch: (request) => Response.text('ok'));
  await server.serve();
}
```

## `entry not found` from osrv CLI

`dart run osrv serve` looks for:

1. `server.dart`
2. `bin/server.dart` (fallback)

If your entry path differs:

```bash
dart run osrv serve --entry path/to/custom_entry.dart
```

## Edge adapter returns 500

Edge adapters require Dart core to register `globalThis.__osrv_main__`.
Ensure your build includes `dist/js/core/<entry>.js` and entry calls `server.serve()`.

## Edge WebSocket returns 501/426

- `426` means request was not a websocket upgrade request (`Upgrade: websocket` missing).
- `501` means current edge provider/runtime does not expose inbound websocket upgrade APIs.

Provider behavior:

1. Cloudflare Workers: websocket upgrade supported.
2. Netlify Edge: requires runtime `Deno.upgradeWebSocket` (or `WebSocketPair`).
3. Vercel Edge: inbound websocket upgrade is not supported.

## HTTP/2 expectation mismatch

Current Dart native transport path uses `dart:io HttpServer`, which does not
negotiate ALPN h2 in this implementation path yet. If you force HTTP/2 clients,
they may fall back to HTTP/1.1.

## Contract matrix failures

Run locally:

```bash
dart run tool/contract_matrix.dart
```

If runtime binaries are missing (`node`, `bun`, `deno`), the script skips them.
In CI contract-matrix job, all runtimes are installed and required.
