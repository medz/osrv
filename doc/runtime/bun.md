# Bun Runtime

## Status

`bun` is implemented as a serve-based JavaScript-host runtime.

## Current Model

Current entry:

```dart
final runtime = await serve(
  server,
  const BunRuntimeConfig(
    host: '127.0.0.1',
    port: 3000,
  ),
);
```

Current support:
- `BunRuntimeConfig`
- `BunRuntimeExtension`
- `Bun.serve(...)` integration
- streaming request bodies
- streaming response bodies
- `onStart`, `onStop`, and `onError`
- request-scoped `waitUntil(...)`
- graceful shutdown that waits for in-flight requests and tracked background work

Current non-support:
- websocket support
- Bun-specific higher-level helpers beyond `BunRuntimeExtension`
- production deployment guidance

## Capabilities

Current capability shape:

```dart
runtime.capabilities.streaming == true
runtime.capabilities.websocket == false
runtime.capabilities.fileSystem == true
runtime.capabilities.backgroundTask == true
runtime.capabilities.rawTcp == true
runtime.capabilities.nodeCompat == true
```

## Runtime Handle

The returned runtime exposes:
- `runtime.info`
- `runtime.capabilities`
- `runtime.url`
- `runtime.close()`
- `runtime.closed`

## Extensions

`BunRuntimeExtension` currently provides:
- `bun`
- `server`
- `request` on request-scoped contexts
