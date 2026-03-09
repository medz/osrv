# Node Runtime

Use the `node` runtime when your app is compiled for a Node.js JavaScript host and should listen through the Node HTTP server.

## Import

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/node.dart';
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

The `node` runtime requires:
- a JavaScript-target build
- a JavaScript host
- the Node `process` object
- the `node:http` module

Compiling this entrypoint for a native target is unsupported and fails during compilation.
When compiled for JavaScript, startup still fails with `UnsupportedError` if the host is not actually Node-compatible.

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

## Runtime Handle

The returned `Runtime` exposes:
- `info.name == 'node'`
- `info.kind == 'server'`
- `capabilities`
- `url`
- `close()`
- `closed`

## `NodeRuntimeExtension`

Use `context.extension<NodeRuntimeExtension>()` when you need Node-specific host access.

It can expose:
- `process`
- `server`
- `request`
- `response`

Example:

```dart
final server = Server(
  fetch: (request, context) {
    final node = context.extension<NodeRuntimeExtension>();
    return Response.json({
      'runtime': context.runtime.name,
      'hasProcess': node?.process != null,
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

- websocket support is not implemented
- the runtime is JavaScript-target only and is not available to native Dart compilation
- Node-specific bridge types are internal implementation detail and should not be imported from `src/`
