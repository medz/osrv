# osrv

Dart-first server runtime with a single `Server(...)` API.

## Status

- Core API: `Server`, middleware, plugins, lifecycle, error handling.
- Runtime transports:
  - `dart:io` (HTTP/1.1, HTTPS, HTTP/2).
  - JS runtimes (Node/Bun/Deno/Edge) via Dart JS interop.
- WebSocket:
  - `dart:io`: supported.
  - Bun/Deno/Cloudflare/Netlify edge: supported.
  - Node/Vercel edge: currently returns `501` for upgrade attempts.

## Install

```bash
dart pub add osrv
```

## Quick Start

```dart
import 'package:osrv/osrv.dart';

Future<void> main() async {
  final server = Server(
    fetch: (request) => Response.json({'ok': true, 'path': request.url.path}),
  );

  await server.serve();
}
```

## CLI

```bash
dart run osrv serve
dart run osrv build
```

`serve` and `build` default to `server.dart` (fallback: `bin/server.dart`).

## Build API

```dart
import 'package:osrv/build.dart';

Future<void> main() async {
  await build(const BuildOptions(entry: 'server.dart', outDir: 'dist'));
}
```

Artifacts:

- `dist/app.js`
- `dist/bin/server` (or `server.exe` on Windows)
- `dist/js/node/index.mjs`
- `dist/js/bun/index.mjs`
- `dist/js/deno/index.mjs`
- `dist/edge/cloudflare/index.mjs`
- `dist/edge/vercel/index.mjs`
- `dist/edge/netlify/index.mjs`

## Example

```bash
cd example
dart pub get
dart run osrv serve
dart run osrv build
```

## Test

Dart tests:

```bash
dart test
```

JS runtime integration tests (Bun-managed project under `test/js`):

```bash
bun install --cwd test/js
bun test --cwd test/js
```

## Docs

- [`docs/troubleshooting.md`](docs/troubleshooting.md)
- [`docs/examples.md`](docs/examples.md)
