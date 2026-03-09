# Cloudflare Runtime

Use the `cloudflare` runtime when you want to export a fetch handler for a Cloudflare Worker.

## Imports

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/cloudflare.dart';
```

## Define the Entry

```dart
void main() {
  defineFetchExport(
    server,
  );
}
```

Optional custom export name:

```dart
defineFetchExport(
  server,
  name: '__custom_fetch__',
);
```

The default export name is `__osrv_fetch__`.

## JavaScript Shim

Compile the Dart entry to JavaScript, then re-export the generated fetch handler:

```js
import './cloudflare.dart.js';

export default { fetch: globalThis.__osrv_fetch__ };
```

If you pass `name: '__custom_fetch__'` to `defineFetchExport(...)`, re-export
`globalThis.__custom_fetch__` instead.

## Runtime Model

Cloudflare currently uses the entry-export model.

That means:
- use `defineFetchExport(...)`
- there is no listener config type
- there is no running `Runtime` handle returned from `main()`

## Capabilities

| Capability | Value |
| --- | --- |
| `streaming` | `true` |
| `websocket` | `false` |
| `fileSystem` | `false` |
| `backgroundTask` | `true` |
| `rawTcp` | `false` |
| `nodeCompat` | `true` |

## `CloudflareRuntimeExtension`

Use:

```dart
final cf =
    context.extension<CloudflareRuntimeExtension<Object?, web.Request>>();
```

The extension can expose:
- `env`
- `context`
- `request`

`context` is a `CloudflareExecutionContext`.

Example:

```dart
import 'package:web/web.dart' as web;

final server = Server(
  fetch: (request, context) {
    final cf =
        context.extension<CloudflareRuntimeExtension<Object?, web.Request>>();
    return Response.json({
      'runtime': context.runtime.name,
      'hasEnv': cf?.env != null,
    });
  },
);
```

## Background Work

Use `context.waitUntil(...)` normally.

On Cloudflare, `osrv` forwards it to the worker execution context when available.

## Current Limitations

- websocket support is not implemented
- `defineFetchExport(...)` requires a JavaScript host
- there is no listener-style `serve(...)` API for Cloudflare
