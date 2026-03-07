# Node Runtime Usage

## Purpose

This document is the short user-facing guide for the current `node` runtime family.

If you only want to know how to start a Node server with `osrv`, start here.

## Basic Start

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/node.dart';

Future<void> main() async {
  final server = Server(
    fetch: (request, context) {
      return Response.json({
        'runtime': context.runtime.name,
        'path': request.url.path,
      });
    },
  );

  final runtime = await serve(
    server,
    const NodeRuntimeConfig(
      host: '127.0.0.1',
      port: 3000,
    ),
  );

  print(runtime.url);
}
```

## Current Support

Currently supported:
- HTTP serving through `node:http`
- request bridge into `ht.Request`
- response bridge from `ht.Response`
- streaming request bodies
- streaming response bodies
- repeated headers such as `set-cookie`
- `onStart`, `onStop`, and `onError`
- request-scoped `waitUntil(...)`
- graceful shutdown that waits for in-flight requests

## Current Non-Support

Currently not supported:
- websocket upgrades
- explicit raw socket APIs
- signal handling
- advanced timeout tuning
- production deployment guidance

## Config

Current config shape:

```dart
const NodeRuntimeConfig({
  this.host = '127.0.0.1',
  this.port = 3000,
});
```

Notes:
- use `port: 0` when you want an ephemeral port
- read the actual listener back from `runtime.url`

## Runtime Handle

The returned runtime gives you:
- `runtime.info`
- `runtime.capabilities`
- `runtime.url`
- `runtime.close()`
- `runtime.closed`

Typical shutdown shape:

```dart
final runtime = await serve(server, const NodeRuntimeConfig(port: 3000));

await runtime.close();  // initiate graceful shutdown
await runtime.closed;   // wait until the runtime is fully closed
```

## Capabilities

Current capability shape for `node`:

```dart
runtime.capabilities.streaming == true
runtime.capabilities.websocket == false
runtime.capabilities.fileSystem == true
runtime.capabilities.backgroundTask == true
runtime.capabilities.rawTcp == true
runtime.capabilities.nodeCompat == true
```

Use capabilities to branch on real support, not assumptions.

## When To Use `NodeRuntimeExtension`

Most application code should not need it.

Use `NodeRuntimeExtension` only when you truly need host-specific access such as:
- the Node `process`
- the underlying Node server object
- the current Node request/response host objects

Example:

```dart
final server = Server(
  fetch: (request, context) {
    final node = context.extension<NodeRuntimeExtension>();
    final version = node?.process?.versions.node;

    return Response.json({
      'runtime': context.runtime.name,
      'nodeVersion': version,
    });
  },
);
```

If normal `Request`, `Response`, `RequestContext`, and capabilities are enough, stay on those.

## Related Documents

- [node.md](./node.md)
- [node-host-model.md](./node-host-model.md)
- [node-http-host.md](./node-http-host.md)
- [node-request-bridge.md](./node-request-bridge.md)
