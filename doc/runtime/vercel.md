# Vercel Runtime

Use the `vercel` runtime when you want to export a fetch handler for Vercel and access helpers from `@vercel/functions`.

## Host Requirements

`osrv`'s Vercel entry is a JavaScript fetch export hosted by Vercel's Node.js function runtime.

Required host setup:

- add `@vercel/functions` to the deploying project's `package.json`
- use an ESM JavaScript entrypoint, preferably `.mjs`
- provide a JavaScript bootstrap that sets `globalThis.self ??= globalThis` before loading the compiled Dart output
- provide a minimal `vercel.json` that rewrites requests to the function entry

Example project files:

```json
{
  "private": true,
  "dependencies": {
    "@vercel/functions": "^3.4.3"
  }
}
```

```json
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "rewrites": [
    {
      "source": "/(.*)",
      "destination": "/api"
    }
  ]
}
```

## Imports

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/vercel.dart';
import 'package:web/web.dart' as web;
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

Compile the Dart entry to JavaScript into your Vercel function directory:

```bash
mkdir -p api
dart compile js vercel.dart -o api/index.dart.js
```

Then bootstrap the generated fetch handler from JavaScript:

```js
globalThis.self ??= globalThis;
import "./index.dart.js";

export default { fetch: globalThis.__osrv_fetch__ };
```

Put that bootstrap in `api/index.mjs`.

If you pass `name: '__custom_fetch__'` to `defineFetchExport(...)`, export
`globalThis.__custom_fetch__` instead.

`globalThis.self` must exist before the compiled Dart module evaluates.
Setting it from Dart or JS interop is too late, because the failure happens during module initialization, before any Dart-side callback can run.

Current Vercel routing still expects Node.js functions inside `/api`. A root-level `vercel.mjs` is not enough by itself; as of Vercel's current docs, the default function discovery model is files under `/api`, and same-application rewrites target paths like `/api/sharp`.

## Runtime Model

Vercel currently uses the entry-export model.

That means:

- use `defineFetchExport(...)`
- there is no listener config type
- there is no running `Runtime` handle returned from `main()`

## Capabilities

| Capability       | Value   |
| ---------------- | ------- |
| `streaming`      | `true`  |
| `websocket`      | `false` |
| `fileSystem`     | `true`  |
| `backgroundTask` | `true`  |
| `rawTcp`         | `false` |
| `nodeCompat`     | `true`  |

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
- `defineFetchExport(...)` requires a JavaScript host
- there is no listener-style `serve(...)` API for Vercel
