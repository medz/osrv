# Node Runtime

## Purpose

This document describes the current `node` runtime family in `osrv`.

`node` means the JavaScript-host runtime backed by Node.js host APIs.
It is the second implemented runtime family after `dart`.

## Status

Current state:
- implemented as a working runtime family
- served through `node:http`
- backed by modern Dart JS interop
- validated by VM-side bridge tests and Node-platform integration tests

It is still not feature-complete.
The goal of the current implementation is a stable HTTP serving baseline, not full Node feature coverage.

## Entry Shape

Current user-facing entry:

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/node.dart';

final runtime = await serve(
  server,
  const NodeRuntimeConfig(
    host: '127.0.0.1',
    port: 3000,
  ),
);
```

## Config

Current config type:

```dart
const NodeRuntimeConfig({
  this.host = '127.0.0.1',
  this.port = 3000,
});
```

Field meanings:
- `host`: listen host
- `port`: listen port; `0` allows an ephemeral port

Current validation:
- `host` must not be empty
- `port` must be between `0` and `65535`

## Capabilities

Current capability declaration:

```dart
const RuntimeCapabilities(
  streaming: true,
  websocket: false,
  fileSystem: true,
  backgroundTask: true,
  rawTcp: true,
  nodeCompat: true,
);
```

Interpretation:
- `streaming: true`
  because request and response body streaming are implemented over Node HTTP host objects
- `websocket: false`
  because websocket support is not yet part of the current runtime surface
- `fileSystem: true`
  because the host runtime has normal filesystem access
- `backgroundTask: true`
  because request-scoped `waitUntil(...)` work is tracked during shutdown
- `rawTcp: true`
  because the host runtime is Node.js
- `nodeCompat: true`
  because this runtime is the Node.js host family

## Runtime Handle

The running `Runtime` currently exposes:
- `info.name == "node"`
- `info.kind == "server"`
- `capabilities`
- `url`
- `close()`
- `closed`

The `url` reflects the resolved Node listener address and port.

## Host Model

Current host entry:

```text
node:http
  -> createServer((req, res) => ...)
  -> IncomingMessage
  -> ServerResponse
```

Interop direction:
- `dart:js_interop` is the primary Node interop layer
- `dart:js_interop_unsafe` is used narrowly where static interop is insufficient
- `package:web` is used only in Node-platform tests for standard Web APIs such as `fetch`
- `ht` remains the internal cross-runtime HTTP model

See [node-host-model.md](./node-host-model.md) for the architectural baseline.

## Request Bridge

Current request bridge behavior:
- reads method, url, and headers from `IncomingMessage`
- resolves request URL against the active listener origin
- bridges body into `ht.Request`
- preserves streaming request bodies
- propagates request body `error` and `aborted` failures

The current bridge path is:

```text
IncomingMessage
  -> nodeRequestFromHost(...)
  -> ht.Request
```

See [node-request-bridge.md](./node-request-bridge.md) for the bridge details.

## Response Bridge

Current response bridge behavior:
- writes status and status text to `ServerResponse`
- writes repeated headers such as `set-cookie`
- streams response body chunks through `write(...)`
- completes the response through `end()`
- propagates `write` and `end` host failures

Conceptually:

```text
ht.Response
  -> writeHtResponseToNodeServerResponse(...)
  -> ServerResponse
```

## Extensions

Current request and lifecycle contexts can expose `NodeRuntimeExtension`.

It currently provides:
- `process`
- `server`
- `request` on request-scoped contexts
- `response` on request-scoped contexts

This is the current escape hatch for Node host-specific details.

## Lifecycle

Current lifecycle behavior:
- config is validated before startup
- host detection and `node:http` availability are checked through preflight
- startup hook failures become `RuntimeStartupError`
- `onStop` runs during shutdown
- request-scoped `waitUntil(...)` tasks are awaited during shutdown
- in-flight request handlers are awaited during shutdown
- `close()` waits for shutdown completion
- `closed` completes with an error if shutdown fails

## Error Handling

Current request behavior:
- if `fetch` throws and `onError` returns a response, that response is written
- if `fetch` throws and `onError` does not handle it, a default `500 Internal Server Error` response is written
- request body stream failures are surfaced
- response write/end failures are surfaced

Current startup behavior:
- invalid config throws `RuntimeConfigurationError`
- non-Node or incomplete host environments throw `UnsupportedError`
- startup hook failures throw `RuntimeStartupError`

## Current Limits

Not implemented yet:
- websocket upgrades
- raw socket APIs above plain capability exposure
- signal handling
- advanced timeout tuning
- explicit client disconnect policy above raw host errors
- richer Node runtime extensions
- production deployment guidance

## Related Documents

- [node-usage.md](./node-usage.md)
- [node-host-model.md](./node-host-model.md)
- [node-http-host.md](./node-http-host.md)
- [node-request-bridge.md](./node-request-bridge.md)
