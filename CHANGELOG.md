# Changelog

## 0.1.0

- Initial public release.
- Dart-first `Server` core with lifecycle, middleware, plugins, and error handling.
- Unified runtime adapters for Dart native, Node, Bun, Deno, and edge providers.
- Unified WebSocket API with `upgradeWebSocket()` and `toResponse()` behavior.
- TLS and HTTP/2 support with runtime capability exposure.
- CLI commands: `dart run osrv serve` and `dart run osrv build`.
- Build artifacts for `dist/js/*`, `dist/edge/*`, and `dist/bin/*`.
