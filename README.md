# osrv

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
[![Dart SDK](https://img.shields.io/badge/dart-%5E3.10.0-0175C2?logo=dart)](https://dart.dev/)
[![GitHub stars](https://img.shields.io/github/stars/medz/osrv?style=social)](https://github.com/medz/osrv)

`osrv` is a unified server runtime for Dart applications.

It provides one portable `Server` contract and explicit runtime entrypoints for:
- `dart`
- `node`
- `bun`
- `cloudflare`
- `vercel`

`osrv` is a runtime layer focused on running the same server contract across different host families, while keeping runtime capabilities and host-specific extensions explicit.

## Why osrv

Use `osrv` when you want:
- one request-handling contract across multiple runtime families
- explicit runtime selection instead of host auto-detection
- honest capability reporting instead of fake cross-platform uniformity
- typed runtime extensions for host-specific access

## Features

- Unified `Server` contract built around `Request`, `Response`, and `RequestContext`
- Explicit runtime selection through `RuntimeConfig` or `defineFetchEntry(...)`
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
| `dart` | `serve(server, DartRuntimeConfig(...))` | `package:osrv/runtime/dart.dart` |
| `node` | `serve(server, NodeRuntimeConfig(...))` | `package:osrv/runtime/node.dart` |
| `bun` | `serve(server, BunRuntimeConfig(...))` | `package:osrv/runtime/bun.dart` |
| `cloudflare` | `defineFetchEntry(server, runtime: FetchEntryRuntime.cloudflare)` | `package:osrv/runtime/cloudflare.dart` + `package:osrv/esm.dart` |
| `vercel` | `defineFetchEntry(server, runtime: FetchEntryRuntime.vercel)` | `package:osrv/runtime/vercel.dart` + `package:osrv/esm.dart` |

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
    const DartRuntimeConfig(host: '127.0.0.1', port: 3000),
  );

  print('Listening on ${runtime.url}');
}
```

### Fetch-Export Runtime

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/esm.dart';

void main() {
  defineFetchEntry(
    Server(
      fetch: (request, context) => Response.text('Hello from osrv'),
    ),
    runtime: FetchEntryRuntime.cloudflare,
  );
}
```

Example JavaScript shim:

```js
import './cloudflare.dart.js';

export default { fetch: globalThis.__osrv_fetch__ };
```

## Core API

The public core entrypoint is `package:osrv/osrv.dart`.

Main exported concepts:
- `Server`
- `serve(...)`
- `Runtime`
- `RuntimeConfig`
- `RequestContext`
- `RuntimeCapabilities`
- `RuntimeExtension`

For fetch-export runtimes, use `package:osrv/esm.dart`.

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

## Examples

The [`example`](./example) directory contains runnable minimal entries for:
- `dart`
- `node`
- `bun`
- `cloudflare`
- `vercel`

## License

[MIT](./LICENSE)
