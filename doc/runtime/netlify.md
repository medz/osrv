# Netlify Runtime

Use the `netlify` runtime when you want to export a fetch handler for Netlify Functions running on Netlify's Node.js function host.

In `osrv`, `netlify` means Netlify Functions only.
It does not mean Netlify Edge Functions.

## Host Requirements

`osrv`'s Netlify entry is a JavaScript fetch export hosted by Netlify Functions.

Required host setup:

- use Netlify Functions, not Netlify Edge Functions
- use an ESM JavaScript entrypoint, preferably `.mjs`
- compile the Dart entry to JavaScript into your Netlify functions directory
- provide a JavaScript bootstrap that sets `globalThis.self ??= globalThis` before loading the compiled Dart output

Netlify Functions currently run on Node.js and require a modern Fetch-based handler model.

## Imports

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/netlify.dart';
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

Compile the Dart entry to JavaScript into your Netlify functions directory:

```bash
mkdir -p netlify/functions
dart compile js netlify.dart -o netlify/functions/index.dart.js
```

Then bootstrap the generated fetch handler from JavaScript:

```js
globalThis.self ??= globalThis;
import './index.dart.js';

const handler = globalThis.__osrv_fetch__;

if (typeof handler !== 'function') {
  throw new Error(
    "Missing '__osrv_fetch__' export. Ensure defineFetchExport(...) ran in the compiled Dart entry.",
  );
}

export default handler;
```

Put that bootstrap in `netlify/functions/index.mjs`.

If you pass `name: '__custom_fetch__'` to `defineFetchExport(...)`, export
`globalThis.__custom_fetch__` instead.

If you need Netlify route config, define it in the JavaScript shim:

```js
export const config = {
  path: '/*',
};
```

That keeps Netlify's route-selection details explicit in the host bootstrap instead of pushing them into `osrv`'s shared core API.

`globalThis.self` must exist before the compiled Dart module evaluates.
Setting it from Dart or JS interop is too late, because the failure happens during module initialization, before any Dart-side callback can run.

## Runtime Model

Netlify Functions currently use the entry-export model.

That means:

- use `defineFetchExport(...)`
- there is no listener config type
- there is no running `Runtime` handle returned from `main()`

`Server.onStart` runs lazily on the first incoming request, not during module load.
`Server.onStop` does not have an automatic shutdown callback in this host model.

That means:

- use `Server.onStart` for lazy initialization that can safely happen on first request
- do not rely on `Server.onStop` for cleanup, because Netlify Functions do not expose a matching shutdown lifecycle hook

## Capabilities

| Capability | Value |
| --- | --- |
| `streaming` | `true` |
| `websocket` | `false` |
| `fileSystem` | `true` |
| `backgroundTask` | `request-dependent` |
| `rawTcp` | `false` |
| `nodeCompat` | `true` |

`backgroundTask` is `true` only when the current invocation exposes Netlify's `waitUntil(...)` hook.
When that hook is absent, `context.capabilities.backgroundTask` is `false`.

## `NetlifyRuntimeExtension`

Use:

```dart
final netlify =
    context.extension<NetlifyRuntimeExtension<web.Request>>();
```

The extension can expose:

- `context`
- `request`

`context` is a `NetlifyContext`.

## `NetlifyContext`

Current helpers and fields:

- `account`
- `cookies`
- `deploy`
- `geo`
- `ip`
- `params`
- `requestId`
- `server`
- `site`

Use `context.waitUntil(...)` normally for background work.
On Netlify, `osrv` forwards it to the function context's `waitUntil(...)` integration when available.
If the current invocation does not expose `waitUntil(...)`, `context.capabilities.backgroundTask` is `false`.

## Example

```dart
import 'package:web/web.dart' as web;

final server = Server(
  fetch: (request, context) {
    final netlify =
        context.extension<NetlifyRuntimeExtension<web.Request>>();
    return Response.json({
      'runtime': context.runtime.name,
      'request': netlify?.request?.url ?? request.url,
      'ip': netlify?.context?.ip,
      'requestId': netlify?.context?.requestId,
    });
  },
);
```

## Counterexample

Do not treat `netlify` as a listener runtime:

```dart
import 'package:osrv/runtime/netlify.dart';

Future<void> main() async {
  await serve(server, port: 3000);
}
```

That is not a valid API.
`netlify` does not expose `serve(...)`.

Do not use this runtime for Netlify Edge Functions.
If you need Deno-based edge middleware or `context.next()`, that is a different host model and is intentionally out of scope for this runtime family.

## Current Limitations

- websocket support is not implemented
- the runtime entry is JavaScript-target only and does not compile to native executables
- there is no listener-style `serve(...)` API for Netlify
- `backgroundTask` depends on Netlify's function-context `waitUntil(...)` support at deploy time
