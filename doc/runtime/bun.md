# Bun Runtime

Use the `bun` runtime when your app is compiled for a Bun JavaScript host and should listen through `Bun.serve(...)`.

## Import

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/bun.dart';
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

The `bun` runtime requires:
- a JavaScript-target build
- a JavaScript host
- the global `Bun` object
- `Bun.serve`

Compiling this entrypoint for a native target is unsupported and fails during compilation.
When compiled for JavaScript, startup fails with `UnsupportedError` if the host does not expose Bun APIs.

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
| `rawTcp` | `false` |
| `nodeCompat` | `true` |

## Runtime Handle

The returned `Runtime` exposes:
- `info.name == 'bun'`
- `info.kind == 'server'`
- `capabilities`
- `url`
- `close()`
- `closed`

## `BunRuntimeExtension`

Use `context.extension<BunRuntimeExtension>()` when you need Bun-specific host access.

It can expose:
- `bun`
- `server`
- `request`

Example:

```dart
final server = Server(
  fetch: (request, context) {
    final bun = context.extension<BunRuntimeExtension>();
    return Response.json({
      'runtime': context.runtime.name,
      'hasBun': bun?.bun != null,
    });
  },
);
```

## Lifecycle and Errors

Current behavior:
- config validation happens before startup
- unsupported-host startup fails explicitly
- `onStart`, `onStop`, and `onError` are supported
- `waitUntil(...)` is tracked during shutdown

## Current Limitations

- websocket support is not implemented in the `osrv` surface
- the runtime is JavaScript-target only and is not available to native Dart compilation
