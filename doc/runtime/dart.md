# Dart Runtime

Use the `dart` runtime when you want a native `dart:io` listener.

## Import

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/dart.dart';
```

## Start a Server

```dart
final runtime = await serve(
  server,
  host: '127.0.0.1',
  port: 3000,
);
```

`runtime.url` contains the bound listener URL.

## Parameters

```dart
serve(
  server,
  host: '127.0.0.1',
  port: 3000,
  backlog: 0,
  shared: false,
  v6Only: false,
);
```

Notes:
- use `port: 0` for an ephemeral port
- `backlog`, `shared`, and `v6Only` map to `HttpServer.bind`

Validation:
- `host` must not be empty
- `port` must be between `0` and `65535`
- `backlog` must not be negative

## Capabilities

| Capability | Value |
| --- | --- |
| `streaming` | `true` |
| `websocket` | `true` |
| `fileSystem` | `true` |
| `backgroundTask` | `true` |
| `rawTcp` | `true` |
| `nodeCompat` | `false` |

## Runtime Handle

The returned `Runtime` exposes:
- `info.name == 'dart'`
- `info.kind == 'server'`
- `capabilities`
- `url`
- `close()`
- `closed`

## `DartRuntimeExtension`

Use `context.extension<DartRuntimeExtension>()` when you need `dart:io` objects.

It can expose:
- `server`
- `request`
- `response`

Example:

```dart
final server = Server(
  fetch: (request, context) {
    final dart = context.extension<DartRuntimeExtension>();
    return Response.json({
      'runtime': context.runtime.name,
      'hasRequest': dart?.request != null,
    });
  },
);
```

## Lifecycle and Errors

Current behavior:
- config validation happens before bind
- bind failures throw `RuntimeStartupError`
- `onStart` failures throw `RuntimeStartupError`
- `onStop` runs during shutdown
- `waitUntil(...)` tasks are awaited during shutdown
- active websocket sessions are closed during shutdown and keep `Runtime.close()` pending until they finish
- `onError` can translate request exceptions into a response

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

Current `dart` runtime websocket behavior:
- `context.capabilities.websocket == true`
- `context.webSocket` is always present for request handlers
- `accept(...)` validates the selected protocol against the client handshake
- returning a manual HTTP `101` without `context.webSocket.accept(...)` is rejected as invalid runtime usage

## Current Limitations

- there is no built-in signal handling policy
- graceful connection draining is minimal
