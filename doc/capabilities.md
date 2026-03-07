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
| `dart` | `serve(...)` | `true` | `false` | `true` | `true` | `true` | `false` |
| `node` | `serve(...)` | `true` | `false` | `true` | `true` | `true` | `true` |
| `bun` | `serve(...)` | `true` | `false` | `true` | `true` | `false` | `true` |
| `cloudflare` | `defineFetchEntry(...)` | `true` | `false` | `false` | `true` | `false` | `true` |
| `vercel` | `defineFetchEntry(...)` | `true` | `false` | `true` | `true` | `false` | `true` |

## What Each Field Means

### `streaming`

The runtime can stream response bodies without forcing everything through one buffered payload.

### `websocket`

The runtime supports websocket handling through the current `osrv` surface.

Current status:
- `false` for every runtime family

### `fileSystem`

The runtime has meaningful filesystem access in its normal execution model.

### `backgroundTask`

The runtime supports request-scoped background work through `RequestContext.waitUntil(...)` or an equivalent host integration.

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
  const NodeRuntimeConfig(port: 3000),
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
