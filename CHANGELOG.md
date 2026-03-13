## Unreleased

## 0.4.0

### Breaking Changes

- Adopted `ht ^0.3.1` across `osrv` and aligned the exported fetch surface with
  the `ht 0.3.x` request/response model.
- Re-exported `HttpMethod`, `RequestInit`, and `ResponseInit` from
  `package:osrv/osrv.dart`; downstream code should now use the `ht 0.3.x`
  construction patterns for `Request` and `Response`.
- Updated examples and runtime paths to use the new `Response(body, init)`
  semantics instead of the older helper-style response construction.

### Runtime

- Reworked Dart and web-family request entry paths to use runtime-backed
  `Request(...)` construction instead of eager bridge materialization.
- Reworked the Node request bridge so requests enter `Server.fetch` as soon as
  headers are available, while preserving streaming request bodies.
- Tightened Node request body streaming with lazy listener attachment,
  pause/resume backpressure propagation, discard-on-cancel draining, and
  non-deprecated abort detection.
- Streamlined Dart and Node response header writes, including repeated
  `set-cookie` preservation.
- Fixed fetch-export response bridging to preserve `Response.error()` semantics.

### Testing

- Added direct request-bridge coverage for Dart and web request hosts.
- Expanded Node runtime coverage for early request entry, streaming request
  bodies, request backpressure, cancel/discard behavior, and response header
  preservation.

## 0.3.0

### Breaking Changes

- Moved listener startup APIs into runtime-specific entrypoints. Use
  `package:osrv/runtime/dart.dart`, `package:osrv/runtime/node.dart`, and
  `package:osrv/runtime/bun.dart` for `serve(...)`.
- Removed the shared `RuntimeConfig` model and the core `serve(...)` dispatcher.
- Removed the shared fetch-entry surface from `package:osrv/esm.dart`. Use
  runtime-specific `defineFetchExport(...)` entrypoints from
  `package:osrv/runtime/cloudflare.dart` and
  `package:osrv/runtime/vercel.dart`.

### Fixes

- Isolated Cloudflare, Vercel, Node, and Bun runtime graphs so downstream
  consumers only compile the runtime they target.
- Fixed Vercel bootstrap expectations and docs around `@vercel/functions` and
  `globalThis.self` setup.
- Tightened runtime startup and preflight behavior, including Node startup
  gating and Bun host normalization.

### Tooling

- Expanded CI and test coverage for platform-specific runtime paths.
- Added compile-surface checks for native vs. JavaScript runtime entrypoints.

### Documentation

- Updated docs and examples to match the runtime-specific entrypoint model.

## 0.2.0

- Unified core API around `Server`, `RequestContext`, `Runtime`, and `serve(...)`.
- Implemented serve-based runtimes for `dart`, `node`, and `bun`.
- Implemented entry-export runtimes for `cloudflare` and `vercel` through `defineFetchExport(...)`.
- Added runtime capability model and typed runtime extensions.
- Added runtime example entries and finalized runtime/API documentation.

## 0.1.0

- Initial public release.
