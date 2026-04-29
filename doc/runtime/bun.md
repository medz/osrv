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
| `websocket` | `true` |
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
- active websocket sessions are closed during shutdown and keep `Runtime.close()` pending until they finish

## WebSocket Handling

When `context.webSocket` is available, websocket upgrades stay inside the normal `Server.fetch(...)` flow.

Example:

```dart
final server = Server(
  fetch: (request, context) {
    final webSocket = context.webSocket;
    if (webSocket == null || !webSocket.isUpgradeRequest) {
      return Response.text('plain http');
    }

    return webSocket.accept(protocol: 'chat', (socket) async {
      socket.sendText('connected');
      await socket.events.drain<void>();
    });
  },
);
```

Current `bun` runtime websocket behavior:
- `context.capabilities.websocket == true`
- `context.webSocket` is always present for request handlers
- `accept(...)` validates the selected protocol against the client handshake
- returning a manual HTTP `101` without `context.webSocket.accept(...)` is rejected as invalid runtime usage
- upgrades are request-scoped in the public API, but internally bridge through Bun's server-level websocket handlers
- protocol validation is host-managed by Bun; malformed transport input can
  terminate the connection without an observable close frame
- ping/pong controls, compression negotiation, send backpressure state, and
  websocket limit/timeout configuration are not portable `osrv` APIs today

## Current Limitations

- the runtime is JavaScript-target only and is not available to native Dart compilation
