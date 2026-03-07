# Vercel Runtime

Use the `vercel` runtime when you want to export a fetch handler for Vercel and access helpers from `@vercel/functions`.

## Imports

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/esm.dart';
import 'package:osrv/runtime/vercel.dart';
import 'package:web/web.dart' as web;
```

## Define the Entry

```dart
void main() {
  defineFetchEntry(
    server,
    runtime: FetchEntryRuntime.vercel,
  );
}
```

Optional custom export name:

```dart
defineFetchEntry(
  server,
  runtime: FetchEntryRuntime.vercel,
  name: '__custom_fetch__',
);
```

The default export name is `__osrv_fetch__`.

## JavaScript Shim

Compile the Dart entry to JavaScript, then re-export the generated fetch handler:

```js
import './vercel.dart.js';

export default { fetch: globalThis.__osrv_fetch__ };
```

If you pass `name: '__custom_fetch__'` to `defineFetchEntry(...)`, re-export
`globalThis.__custom_fetch__` instead.

## Runtime Model

Vercel currently uses the entry-export model.

That means:
- use `defineFetchEntry(...)`
- there is no `RuntimeConfig`
- there is no running `Runtime` handle returned from `main()`

## Capabilities

| Capability | Value |
| --- | --- |
| `streaming` | `true` |
| `websocket` | `false` |
| `fileSystem` | `true` |
| `backgroundTask` | `true` |
| `rawTcp` | `false` |
| `nodeCompat` | `true` |

## `VercelRuntimeExtension`

Use:

```dart
final vercel =
    context.extension<VercelRuntimeExtension<web.Request>>();
```

The extension can expose:
- `functions`
- `request`

## `VercelFunctions`

`VercelFunctions` is exported from `package:osrv/runtime/vercel.dart`.

Current helpers:
- `waitUntil(...)`
- `env`
- `geolocation`
- `ipAddress`
- `invalidateByTag(...)`
- `dangerouslyDeleteByTag(...)`
- `invalidateBySrcImage(...)`
- `dangerouslyDeleteBySrcImage(...)`
- `addCacheTag(...)`
- `getCache(...)`
- `attachDatabasePool(...)`

`getCache(...)` returns `VercelRuntimeCache`.

## Background Work

Use `context.waitUntil(...)` normally.

On Vercel, `osrv` forwards it to the helper bag loaded from `@vercel/functions`.

## Example

```dart
import 'package:web/web.dart' as web;

final server = Server(
  fetch: (request, context) {
    final vercel =
        context.extension<VercelRuntimeExtension<web.Request>>();
    return Response.json({
      'runtime': context.runtime.name,
      'hasFunctions': vercel?.functions != null,
    });
  },
);
```

## Current Limitations

- websocket support is not implemented
- `defineFetchEntry(...)` requires a JavaScript host
- there is no listener-style `serve(...)` API for Vercel
