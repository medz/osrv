# osrv Architecture

`osrv` is a runtime layer for Dart applications.

It gives you:
- one `Server` contract
- explicit runtime selection
- a shared lifecycle model
- a capability model
- typed runtime extensions for host-specific access

It does not give you:
- a router DSL
- middleware composition primitives
- automatic runtime detection
- one giant cross-platform config object

## The Two Entry Models

`osrv` currently supports two explicit entry models.

### 1. Serve-Based Runtimes

Use the runtime-specific `serve(server, {platform params})` entrypoint when the host owns a long-lived listener.

Current serve-based runtimes:
- `dart`
- `node`
- `bun`
- `deno`

Example:

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/dart.dart';

final runtime = await serve(
  server,
  host: '127.0.0.1',
  port: 3000,
);
```

### 2. Entry-Export Runtimes

Use runtime-specific `defineFetchExport(server)` when the host expects a fetch handler export instead of a running listener.

Current entry-export runtimes:
- `cloudflare`
- `vercel`
- `netlify`

Example:

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/cloudflare.dart';

void main() {
  defineFetchExport(
    server,
  );
}
```

## Request Flow

The shared request model is:

```text
host request
  -> runtime bridge
  -> Server.fetch(request, context)
  -> ht.Response
  -> runtime bridge
  -> host response
```

That gives application code one stable shape while still letting each runtime keep its own host behavior.

## Lifecycle Model

The common lifecycle surface is:
- `Server.fetch(...)` for request handling
- `Server.onStart` for runtime startup
- `Server.onStop` for runtime shutdown
- `Server.onError` for request-level error translation
- `RequestContext.waitUntil(...)` for background work where supported

Serve-based runtimes also return a `Runtime` handle with:
- `info`
- `capabilities`
- `url`
- `close()`
- `closed`

Entry-export runtimes do not return a running `Runtime`.

## Capability Model

`osrv` unifies the server shape, not host power.

Use capabilities to branch on real host truth:
- `streaming`
- `websocket`
- `fileSystem`
- `backgroundTask`
- `rawTcp`
- `nodeCompat`

Current status:
- `dart` implements websocket handling through the current `osrv` surface
- `node` implements websocket handling through the current `osrv` surface
- `bun` implements websocket handling through the current `osrv` surface
- `deno` implements websocket handling through the current `osrv` surface
- `cloudflare` implements websocket handling through the current `osrv` surface
- other runtime families still report `websocket == false`

See [capabilities](./capabilities.md) for the current matrix.

## Runtime Extensions

When you need host-specific behavior, use a typed runtime extension from the request or lifecycle context.

Examples:
- `DartRuntimeExtension`
- `DenoRuntimeExtension`
- `NodeRuntimeExtension`
- `BunRuntimeExtension`
- `CloudflareRuntimeExtension<Env, Request>`
- `VercelRuntimeExtension<Request>`
- `NetlifyRuntimeExtension<Request>`

Extensions expose runtime-specific power without pushing host objects into the common core API.

## Stable Imports

Application code should import only:
- `package:osrv/osrv.dart`
- `package:osrv/runtime/*.dart`

Do not import `package:osrv/src/...`.

See [public surface](./api/public-surface.md) for the exact export list.

## Related Docs

- [config](./config.md)
- [capabilities](./capabilities.md)
- [core API](./api/core.md)
- [runtime API](./api/runtime.md)
- [runtime docs](./runtime/README.md)
- [usage examples](./examples/final-usage.md)
