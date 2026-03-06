# Dart Runtime

## Purpose

This document describes the current `dart` runtime family in `osrv`.

`dart` means the host runtime backed by `dart:io`.
It is the first proof runtime for the current `osrv` contract.

## Status

Current state:
- implemented as a working serve-based runtime
- backed by `dart:io`
- validated by VM-side and integration tests

## Entry Shape

Current user-facing entry:

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/dart.dart';

final runtime = await serve(
  server,
  const DartRuntimeConfig(
    host: '127.0.0.1',
    port: 3000,
  ),
);
```

## Config

Current config type:

```dart
const DartRuntimeConfig({
  this.host = '127.0.0.1',
  this.port = 3000,
  this.backlog = 0,
  this.shared = false,
  this.v6Only = false,
});
```

Field meanings:
- `host`: bind host
- `port`: bind port; `0` allows an ephemeral port
- `backlog`: listener backlog passed to `HttpServer.bind`
- `shared`: whether the listener is shared
- `v6Only`: whether IPv6 sockets reject IPv4 mapping

Current validation:
- `host` must not be empty
- `port` must be between `0` and `65535`
- `backlog` must not be negative

## Capabilities

Current capability declaration:

```dart
const RuntimeCapabilities(
  streaming: true,
  websocket: false,
  fileSystem: true,
  backgroundTask: true,
  rawTcp: true,
  nodeCompat: false,
);
```

Interpretation:
- `streaming: true`
  because response body streams are supported through `dart:io`
- `websocket: false`
  because websocket handling is not yet part of the current runtime surface
- `fileSystem: true`
  because the host runtime has normal filesystem access
- `backgroundTask: true`
  because request-scoped `waitUntil(...)` work is tracked during shutdown
- `rawTcp: true`
  because the host runtime supports low-level sockets
- `nodeCompat: false`
  because this runtime is not Node.js

## Runtime Handle

The running `Runtime` currently exposes:
- `info.name == "dart"`
- `info.kind == "server"`
- `capabilities`
- `url`
- `close()`
- `closed`

The `url` currently reflects the bound host and port.

## Extensions

Current request and lifecycle contexts can expose `DartRuntimeExtension`.

It currently provides:
- `server`
- `request` on request-scoped contexts
- `response` on request-scoped contexts

This is the current escape hatch for `dart:io` host-specific details.

## Lifecycle

Current lifecycle behavior:
- config is validated before bind
- bind failures become `RuntimeStartupError`
- `onStart` failures become `RuntimeStartupError`
- `onStop` runs during shutdown
- request-scoped `waitUntil(...)` tasks are awaited during shutdown
- `close()` waits for shutdown completion
- `closed` completes with an error if shutdown fails

## Error Handling

Current request behavior:
- if `fetch` throws and `onError` returns a response, that response is written
- if `fetch` throws and `onError` does not handle it, a default `500 Internal Server Error` response is written

Current startup behavior:
- invalid config throws `RuntimeConfigurationError`
- bind/start hook failures throw `RuntimeStartupError`

## Current Limits

Current non-support:
- websocket support
- richer runtime extensions
- advanced response bridge edge cases
- host signal integration
- graceful connection draining policy
- dedicated `dart` runtime documentation for production deployment

## Related Documents

- [dart-usage.md](./dart-usage.md)
