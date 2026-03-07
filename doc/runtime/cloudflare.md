# Cloudflare Runtime

## Status

`cloudflare` is implemented as an explicit fetch-export host.

It is not part of the `serve(...) -> Runtime` family.

## Entry Shape

```dart
import 'package:osrv/esm.dart';

void main() {
  defineFetchEntry(
    server,
    runtime: FetchEntryRuntime.cloudflare,
  );
}
```

This publishes a fetch handler to `globalThis`.

The default name is:
- `__osrv_fetch__`

## JS Shim

The intended deploy shim is intentionally thin:

```js
import './cloudflare.dart.js';

export default { fetch: globalThis.__osrv_fetch__ };
```

## Request Context

`cloudflare` request handling still enters the normal `Server.fetch(...)` contract.

Runtime-specific data is available through:

```dart
import 'package:osrv/runtime/cloudflare.dart';
import 'package:web/web.dart' as web;

final cf = context.extension<
    CloudflareRuntimeExtension<Env, web.Request>>();
```

The extension currently carries:
- `env`
- `context`
- `request`

## waitUntil

In `cloudflare`, `context.waitUntil(...)` is a direct mapping to the host-native Worker execution context.

It is not a simulated queue owned by `osrv`.

That means:
- `backgroundTask` is a real runtime capability
- request-scoped background work uses native Worker semantics

## Current Scope

Current support:
- `fetch`
- typed runtime extension access
- native `waitUntil(...)` forwarding
- streaming request bodies
- streaming response bodies
- `onStart`
- `onError`

Current non-support:
- `scheduled`
- `queue`
- `email`
- `tail`
- a `Runtime` handle from `serve(...)`
