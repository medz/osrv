# Changelog

## Unreleased

- Refactor: `ServerRequest` is now an interface with server getters only.
- Removed mutable `ServerRequest` runtime/ip/context setter/defer APIs and websocket request state mutators.
- `ServerRequest.clone()` / `copyWith()` now preserve request data and reset server metadata.
- JS transport switched from JSON bridge payloads to direct `__osrv_main__(request, context)` dispatch.
- Runtime templates removed bridge fallback branches and call Dart handler directly.

## 0.1.0

- Initial public release.
- Dart-first `Server` core with lifecycle, middleware, plugins, and error handling.
- Unified runtime adapters for Dart native, Node, Bun, Deno, and edge providers.
- Unified WebSocket API with `upgradeWebSocket()` and `toResponse()` behavior.
- TLS and HTTP/2 support with runtime capability exposure.
- CLI commands: `dart run osrv serve` and `dart run osrv build`.
- Build artifacts for `dist/js/*`, `dist/edge/*`, and `dist/bin/*`.
