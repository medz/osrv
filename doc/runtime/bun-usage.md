# Bun Runtime Usage

## Basic Start

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/bun.dart';

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
    const BunRuntimeConfig(
      host: '127.0.0.1',
      port: 3000,
    ),
  );

  print(runtime.url);
}
```

## Current Support

Currently supported:
- HTTP serving through `Bun.serve(...)`
- request bridge into `ht.Request`
- response bridge from `ht.Response`
- streaming request bodies
- streaming response bodies
- `onStart`, `onStop`, and `onError`
- request-scoped `waitUntil(...)`
- graceful shutdown that waits for in-flight requests

## Current Non-Support

Currently not supported:
- websocket handling in the current runtime surface
- Bun-specific higher-level helpers beyond `BunRuntimeExtension`
- production deployment guidance

## When To Use `BunRuntimeExtension`

Most application code should not need it.

Use `BunRuntimeExtension` only when you truly need host-specific access such as:
- the Bun global
- the underlying Bun server object
- the current Bun request host object
