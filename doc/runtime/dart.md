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
  const DartRuntimeConfig(host: '127.0.0.1', port: 3000),
);
```

`runtime.url` contains the bound listener URL.

## Config

```dart
const DartRuntimeConfig({
  this.host = '127.0.0.1',
  this.port = 3000,
  this.backlog = 0,
  this.shared = false,
  this.v6Only = false,
});
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
| `websocket` | `false` |
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
- `onError` can translate request exceptions into a response

## Current Limitations

- websocket support is not implemented
- there is no built-in signal handling policy
- graceful connection draining is minimal
