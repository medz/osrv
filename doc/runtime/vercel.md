# Vercel Runtime

## Status

`vercel` is implemented as an explicit fetch-export host.

It is not part of the `serve(...) -> Runtime` family.

## Entry Shape

```dart
import 'package:osrv/esm.dart';

void main() {
  defineFetchEntry(
    server,
    runtime: FetchEntryRuntime.vercel,
  );
}
```

## JS Shim

The intended deploy shim is intentionally thin:

```js
import './vercel.dart.js';

export default { fetch: globalThis.__osrv_fetch__ };
```

## Request Context

Runtime-specific data is available through:

```dart
final vercel = context.extension<
    VercelRuntimeExtension<web.Request>>();
```

The extension currently carries:
- `request`
- `functions`

## Functions Facade

`VercelFunctions` currently exposes:
- `waitUntil(...)`
- `env`
- `geolocation`
- `ipAddress`
- cache invalidation helpers
- runtime cache access
- `attachDatabasePool(...)`

## Current Support

Current support:
- `fetch`
- typed runtime extension access
- host helper access through `VercelFunctions`
- streaming request bodies
- streaming response bodies
- `onStart`
- `onError`

Current non-support:
- a `Runtime` handle from `serve(...)`
- websocket support
- non-fetch Vercel entry shapes
