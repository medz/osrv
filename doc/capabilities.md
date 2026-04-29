# osrv Capabilities

`RuntimeCapabilities` tells you what the selected runtime actually supports.

Use it for feature branching.
Do not assume every host behaves like `dart` or `node`.

## Capability Fields

`osrv` currently exposes these booleans:

```dart
final class RuntimeCapabilities {
  const RuntimeCapabilities({
    required this.streaming,
    required this.websocket,
    required this.fileSystem,
    required this.backgroundTask,
    required this.rawTcp,
    required this.nodeCompat,
  });
}
```

## Current Support Matrix

| Runtime | Entry model | streaming | websocket | fileSystem | backgroundTask | rawTcp | nodeCompat |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `dart` | `serve(...)` | `true` | `true` | `true` | `true` | `true` | `false` |
| `node` | `serve(...)` | `true` | `true` | `true` | `true` | `true` | `true` |
| `bun` | `serve(...)` | `true` | `true` | `true` | `true` | `false` | `true` |
| `deno` | `serve(...)` | `true` | `host-dependent` | `true` | `true` | `true` | `true` |
| `cloudflare` | `defineFetchExport(...)` | `true` | `true` | `false` | `true` | `false` | `true` |
| `vercel` | `defineFetchExport(...)` | `true` | `false` | `true` | `true` | `false` | `true` |
| `netlify` | `defineFetchExport(...)` | `true` | `false` | `true` | `request-dependent` | `false` | `true` |

## What Each Field Means

### `streaming`

The runtime can stream response bodies without forcing everything through one buffered payload.

### `websocket`

The runtime supports websocket handling through the current `osrv` surface.
That means the runtime can expose `RequestContext.webSocket`, accept upgrades
through `WebSocketRequest.accept(...)`, deliver text/binary events through the
shared websocket event stream, and close the connected socket through the shared
socket API.

Current status:
- `true` for `dart`
- `true` for `node`
- `true` for `bun`
- `host-dependent` for `deno`
- `true` for `cloudflare`
- `false` for every other runtime family

For `deno`, websocket support depends on whether the current host exposes
`Deno.upgradeWebSocket(...)`. `RuntimeCapabilities.websocket` reflects that
runtime check.

`websocket == true` is not a promise that every advanced transport feature is
portable or identical across runtimes. Protocol validation and close-code
observability can be host-managed. For example, `dart` and `node` expose a
`1007` close for invalid UTF-8 text frames, while `bun` and `deno` can terminate
the connection without a close frame for the same malformed input.

Advanced transport controls are intentionally not implied by this flag:

| Feature | Portable through `osrv` today? |
| --- | --- |
| request-scoped upgrade acceptance | yes |
| text and binary message delivery | yes |
| clean application close | yes |
| protocol-error teardown | yes, with runtime-specific close details |
| ping/pong control surface | no |
| send backpressure or buffered-state reporting | no |
| extension or compression negotiation | no |
| configurable websocket limits or timeouts | no |

### `fileSystem`

The runtime has meaningful filesystem access in its normal execution model.

### `backgroundTask`

The runtime supports request-scoped background work through `RequestContext.waitUntil(...)` or an equivalent host integration.

For `netlify`, this is request-dependent.
`backgroundTask` is `true` only when the current invocation exposes Netlify Functions `waitUntil(...)`.

### `rawTcp`

The runtime has meaningful low-level socket support available in its host model.

### `nodeCompat`

The runtime exposes meaningful Node-compatible behavior or APIs.

## Where You Read Capabilities

For serve-based runtimes:
- `runtime.capabilities`
- `context.capabilities`

For entry-export runtimes:
- `context.capabilities`

Example:

```dart
final runtime = await serve(
  server,
  port: 3000,
);

if (!runtime.capabilities.websocket) {
  // fallback path
}
```

```dart
final server = Server(
  fetch: (request, context) {
    if (!context.capabilities.backgroundTask) {
      return Response.text('background work unavailable', status: 501);
    }

    context.waitUntil(Future<void>.value());
    return Response.text('ok');
  },
);
```

## Capabilities vs Extensions

Use capabilities to answer:
- can this runtime support a feature at all?

Use runtime extensions to answer:
- what host-specific objects or helpers are available?

Examples:
- `context.capabilities.backgroundTask`
- `context.extension<VercelRuntimeExtension<web.Request>>()`

## Important Limitation

Capabilities are intentionally coarse.
They do not replace runtime-specific docs for lifecycle details, host objects, or platform restrictions.
