# osrv

A unified server runtime shape for Dart applications.

## Status

Implemented runtime families:
- `dart` via `serve(server, DartRuntimeConfig(...))`
- `node` via `serve(server, NodeRuntimeConfig(...))`
- `bun` via `serve(server, BunRuntimeConfig(...))`
- `cloudflare` via `defineFetchEntry(server, runtime: FetchEntryRuntime.cloudflare)`
- `vercel` via `defineFetchEntry(server, runtime: FetchEntryRuntime.vercel)`

## Install

```bash
dart pub add osrv
```

## Core Shape

The core API is intentionally small:
- `Server`
- `serve(server, runtimeConfig)` for serve-based runtimes
- `RequestContext`
- `Runtime`
- `RuntimeCapabilities`
- `RuntimeExtension`

## Quick Start: Dart Runtime

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
    const DartRuntimeConfig(
      host: '127.0.0.1',
      port: 3000,
    ),
  );

  print(runtime.url);
}
```

## Quick Start: Cloudflare / Vercel Entry Export

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/esm.dart';

void main() {
  defineFetchEntry(
    Server(
      fetch: (request, context) => Response.text('Hello Osrv!'),
    ),
    runtime: FetchEntryRuntime.cloudflare,
  );
}
```

Then use a thin JS shim:

```js
import './cloudflare.dart.js';

export default { fetch: globalThis.__osrv_fetch__ };
```

## Capability Model

`osrv` unifies server shape, not host power.

Check host truth through capabilities:

```dart
if (!runtime.capabilities.websocket) {
  // explicit fallback
}
```

## Docs

- [architecture](./doc/architecture.md)
- [capabilities](./doc/capabilities.md)
- [config model](./doc/config.md)
- [core API](./doc/api/core.md)
- [runtime API](./doc/api/runtime.md)
- [runtime docs](./doc/runtime/README.md)
- [terms](./doc/terms.md)
- [final usage examples](./doc/examples/final-usage.md)

## Playground

The [`playground`](./playground) directory contains minimal runtime entry samples for:
- `dart`
- `node`
- `bun`
- `cloudflare`
- `vercel`
