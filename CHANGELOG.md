## Unreleased

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
