# Vercel Usage

## Minimal Shape

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/esm.dart';

void main() {
  defineFetchEntry(
    Server(
      fetch: (request, context) => Response.text('Hello Osrv!'),
    ),
    runtime: FetchEntryRuntime.vercel,
  );
}
```

## Default Export

Compile the Dart entry to JavaScript, then use a tiny shim:

```js
import './vercel.dart.js';

export default { fetch: globalThis.__osrv_fetch__ };
```

## Typed Extension Access

```dart
import 'package:osrv/runtime/vercel.dart';
import 'package:web/web.dart' as web;

final vercel = context.extension<
    VercelRuntimeExtension<web.Request>>();
```

Use `vercel?.functions` when you need Vercel-specific helpers such as:
- `waitUntil(...)`
- `env`
- `geolocation`
- `ipAddress`
- cache helpers

## waitUntil

Use `context.waitUntil(...)` normally.

Under `vercel`, it forwards to the host helper bag exposed by `@vercel/functions`.
