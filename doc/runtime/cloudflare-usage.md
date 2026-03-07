# Cloudflare Usage

## Minimal Shape

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

## Default Export

Compile the Dart entry to JavaScript, then use a tiny shim:

```js
import './cloudflare.dart.js';

export default { fetch: globalThis.__osrv_fetch__ };
```

## Typed Extension Access

```dart
import 'dart:js_interop';
import 'package:osrv/runtime/cloudflare.dart';
import 'package:web/web.dart' as web;

final cf = context.extension<
    CloudflareRuntimeExtension<JSObject, web.Request>>();
```

This lets application code treat:
- `env` as a typed host object
- `request` as a typed Web `Request`

## waitUntil

Use `context.waitUntil(...)` normally.

Under `cloudflare`, it forwards to the native Worker execution context.
