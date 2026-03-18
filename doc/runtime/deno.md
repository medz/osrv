# Deno Runtime

Use the `deno` runtime when your app is compiled for a Deno JavaScript host and should listen through `Deno.serve(...)`.

It is a Deno CLI listener runtime.
It is not the Deno Deploy or edge-export model.

## Import

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/deno.dart';
```

## Start a Server

```dart
final runtime = await serve(
  server,
  host: '127.0.0.1',
  port: 3000,
);
```

## Host Requirements

The `deno` runtime requires:

- a JavaScript-target build
- a JavaScript host
- the global `Deno` object
- `Deno.serve`
- permission to open the requested listener, typically `--allow-net`

Compiling this entrypoint for a native target is unsupported and fails during compilation.
When compiled for JavaScript, startup still fails with `UnsupportedError` if the host is not actually Deno.

## Parameters

```dart
serve(
  server,
  host: '127.0.0.1',
  port: 3000,
);
```

Validation:

- `host` must not be empty
- `port` must be between `0` and `65535`

## Capabilities

| Capability | Value |
| --- | --- |
| `streaming` | `true` |
| `websocket` | `false` |
| `fileSystem` | `true` |
| `backgroundTask` | `true` |
| `rawTcp` | `true` |
| `nodeCompat` | `true` |

`nodeCompat == true` means Deno exposes meaningful Node-compatible APIs.
It does not mean the `deno` runtime serves requests through Node `http`.

## Runtime Handle

The returned `Runtime` exposes:

- `info.name == 'deno'`
- `info.kind == 'server'`
- `capabilities`
- `url`
- `close()`
- `closed`

## `DenoRuntimeExtension`

Use `context.extension<DenoRuntimeExtension>()` when you need Deno-specific host access.

It can expose:

- `deno`
- `server`
- `request`

Example:

```dart
final server = Server(
  fetch: (request, context) {
    final deno = context.extension<DenoRuntimeExtension>();
    return Response.json({
      'runtime': context.runtime.name,
      'hasRequest': deno?.request != null,
    });
  },
);
```

## Lifecycle and Errors

Current behavior:

- config validation happens before startup
- unsupported-host startup fails explicitly
- listener bind failures throw `RuntimeStartupError`
- `onStart`, `onStop`, and `onError` are supported
- `waitUntil(...)` work is tracked during shutdown

## What It Is Not

The `deno` runtime in `osrv` does not:

- auto-detect the host and switch to `node` or `bun`
- expose websocket support through the current `osrv` surface
- flatten Deno CLI and Deno Deploy into one fake universal runtime

## Counterexample

Do not use `package:osrv/runtime/deno.dart` when the host expects an exported fetch entry instead of a long-lived listener.

Examples:

- Cloudflare Workers should use `package:osrv/runtime/cloudflare.dart`
- Vercel should use `package:osrv/runtime/vercel.dart`
- Netlify Functions should use `package:osrv/runtime/netlify.dart`

## Current Limitations

- websocket support is not implemented in the `osrv` surface
- the runtime is JavaScript-target only and is not available to native Dart compilation
- Deno permissions are host policy; `osrv` does not emulate missing host capabilities
