# Dart Runtime Usage

## Purpose

This document is the short user-facing guide for the current `dart` runtime family.

If you only want to know how to start a `dart:io` server with `osrv`, start here.

## Basic Start

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/dart.dart';

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
    const DartRuntimeConfig(
      host: '127.0.0.1',
      port: 3000,
    ),
  );

  print(runtime.url);
}
```

## Current Support

Currently supported:
- HTTP serving through `dart:io`
- request bridge into `ht.Request`
- response bridge from `ht.Response`
- streaming request bodies
- streaming response bodies
- repeated headers such as `set-cookie`
- `onStart`, `onStop`, and `onError`
- request-scoped `waitUntil(...)`
- shutdown that waits for tracked background work

## Current Non-Support

Currently not supported:
- websocket handling in the current runtime surface
- signal integration
- production deployment guidance
- richer runtime extensions above the current `dart:io` escape hatch

## Config

Current config shape:

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
- use `port: 0` when you want an ephemeral port
- read the actual listener back from `runtime.url`
- `backlog`, `shared`, and `v6Only` map directly to `HttpServer.bind`

## Runtime Handle

The returned runtime gives you:
- `runtime.info`
- `runtime.capabilities`
- `runtime.url`
- `runtime.close()`
- `runtime.closed`

Typical shutdown shape:

```dart
final runtime = await serve(server, const DartRuntimeConfig(port: 3000));

await runtime.close();
await runtime.closed;
```

## Capabilities

Current capability shape for `dart`:

```dart
runtime.capabilities.streaming == true
runtime.capabilities.websocket == false
runtime.capabilities.fileSystem == true
runtime.capabilities.backgroundTask == true
runtime.capabilities.rawTcp == true
runtime.capabilities.nodeCompat == false
```

Use capabilities to branch on real support, not assumptions.

## When To Use `DartRuntimeExtension`

Most application code should not need it.

Use `DartRuntimeExtension` only when you truly need `dart:io` host-specific access such as:
- the underlying `HttpServer`
- the current `HttpRequest`
- the current `HttpResponse`

Example:

```dart
final server = Server(
  fetch: (request, context) {
    final dart = context.extension<DartRuntimeExtension>();
    final method = dart?.request?.method;

    return Response.json({
      'runtime': context.runtime.name,
      'rawMethod': method,
    });
  },
);
```

If normal `Request`, `Response`, `RequestContext`, and capabilities are enough, stay on those.

## Related Documents

- [dart.md](./dart.md)
- [node-usage.md](./node-usage.md)
