# osrv

[![pub package](https://img.shields.io/pub/v/osrv.svg)](https://pub.dev/packages/osrv)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
[![Dart SDK](https://img.shields.io/badge/dart-%5E3.10.0-0175C2?logo=dart)](https://dart.dev/)
[![CI](https://github.com/medz/osrv/actions/workflows/ci.yml/badge.svg)](https://github.com/medz/osrv/actions/workflows/ci.yml)
[![GitHub stars](https://img.shields.io/github/stars/medz/osrv?style=social)](https://github.com/medz/osrv)

`osrv` is a unified server runtime for Dart applications.

It provides one portable `Server` contract and explicit runtime entrypoints for:
- `dart`
- `node`
- `bun`
- `deno`
- `cloudflare`
- `vercel`
- `netlify`

`osrv` is a runtime layer focused on running the same server contract across different host families, while keeping runtime capabilities and host-specific extensions explicit.

## Why osrv

Use `osrv` when you want:
- one request-handling contract across multiple runtime families
- explicit runtime selection instead of host auto-detection
- honest capability reporting instead of fake cross-platform uniformity
- typed runtime extensions for host-specific access

## Features

- Unified `Server` contract built around `Request`, `Response`, and `RequestContext`
- Explicit runtime selection through runtime-specific `serve(...)` or `defineFetchExport(...)`
- Runtime capability model via `RuntimeCapabilities`
- Lifecycle hooks: `onStart`, `onStop`, and `onError`
- Typed runtime-specific extension access
- Separate entry models for listener runtimes and fetch-export runtimes

## Installation

```bash
dart pub add osrv
```

## Supported Runtimes

| Runtime | Entry model | Import |
| --- | --- | --- |
| `dart` | `serve(server, host: ..., port: ...)` | `package:osrv/runtime/dart.dart` |
| `node` | `serve(server, host: ..., port: ...)` | `package:osrv/runtime/node.dart` |
| `bun` | `serve(server, host: ..., port: ...)` | `package:osrv/runtime/bun.dart` |
| `deno` | `serve(server, host: ..., port: ...)` | `package:osrv/runtime/deno.dart` |
| `cloudflare` | `defineFetchExport(server)` | `package:osrv/runtime/cloudflare.dart` |
| `vercel` | `defineFetchExport(server)` | `package:osrv/runtime/vercel.dart` |
| `netlify` | `defineFetchExport(server)` | `package:osrv/runtime/netlify.dart` |

Target notes:
- `package:osrv/runtime/dart.dart` is the native Dart listener entry.
- `package:osrv/runtime/node.dart`, `package:osrv/runtime/bun.dart`, `package:osrv/runtime/deno.dart`, `package:osrv/runtime/cloudflare.dart`, `package:osrv/runtime/vercel.dart`, and `package:osrv/runtime/netlify.dart` are JavaScript-target runtime entries and intentionally do not compile to native executables.

## Quick Start

### Serve-Based Runtime

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/dart.dart';

Future<void> main() async {
  final server = Server(
    fetch: (request, context) {
      return Response.json({
        'runtime': context.runtime.name,
        'path': request.url.path,
      });
    },
  );

  final runtime = await serve(
    server,
    host: '127.0.0.1',
    port: 3000,
  );

  print('Listening on ${runtime.url}');
}
```

### Fetch-Export Runtime

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/cloudflare.dart';

void main() {
  defineFetchExport(
    Server(
      fetch: (request, context) => Response.text('Hello from osrv'),
    ),
  );
}
```

Example JavaScript shim:

```js
import './cloudflare.dart.js';

export default { fetch: globalThis.__osrv_fetch__ };
```

For Vercel, use a bootstrap entry that sets `globalThis.self ??= globalThis`
before importing the compiled Dart module. The deploying project
must also include `@vercel/functions`, use an ESM entry such as `.mjs`, and provide a minimal
`vercel.json`. See [`doc/runtime/vercel.md`](./doc/runtime/vercel.md).

## Core API

The public core entrypoints are:
- `package:osrv/osrv.dart`
- `package:osrv/websocket.dart` for websocket-specific types

Main exported concepts:
- `Server`
- `Runtime`
- `RequestContext`
- `RuntimeCapabilities`
- `RuntimeExtension`

For runtime entry APIs, use the matching runtime entrypoint such as `package:osrv/runtime/dart.dart`, `package:osrv/runtime/node.dart`, `package:osrv/runtime/bun.dart`, `package:osrv/runtime/cloudflare.dart`, or `package:osrv/runtime/vercel.dart`.

## Documentation

- [Documentation Index](./doc/README.md)
- [Architecture](./doc/architecture.md)
- [Configuration](./doc/config.md)
- [Capabilities](./doc/capabilities.md)
- [Core API](./doc/api/core.md)
- [Runtime API](./doc/api/runtime.md)
- [Public Surface](./doc/api/public-surface.md)
- [Runtime Guides](./doc/runtime/README.md)
- [Usage Examples](./doc/examples/final-usage.md)

## Local CI

You can run the repository's GitHub Actions workflow locally before pushing.

Preferred path:

```bash
brew install act
./tool/ci_local.sh
```

That runs `.github/workflows/ci.yml` locally through
[`nektos/act`](https://github.com/nektos/act), which is specifically designed
to execute GitHub Actions on your machine using Docker.

Useful variants:

```bash
./tool/ci_local.sh analyze
./tool/ci_local.sh --job test-node
./tool/ci_local.sh --native
```

`--native` skips `act` and runs the CI-equivalent commands directly. This is
useful when you want fast local verification or do not have `act` installed.

## Examples

The [`example`](./example) directory contains runnable minimal entries for:
- `dart`
- `node`
- `bun`
- `cloudflare`
- `vercel`

## License

[MIT](./LICENSE)
