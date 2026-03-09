# osrv Terms

This page is a user-facing glossary for the main `osrv` terms.

## Server

`Server` is the portable application contract used by `osrv`.

It provides:
- `fetch`
- optional lifecycle hooks

It is not:
- a listener
- a framework router
- a platform process object

## Runtime Config

Runtime config is the explicit input passed to a serve-based runtime entrypoint.

Current examples:
- `serve(server, host: ..., port: ...)` from `package:osrv/runtime/dart.dart`
- `serve(server, host: ..., port: ...)` from `package:osrv/runtime/node.dart`
- `serve(server, host: ..., port: ...)` from `package:osrv/runtime/bun.dart`

It is input, not the running runtime handle.

## Entry Export

An entry export is a runtime entry that publishes a fetch handler without returning a running `Runtime`.

Current examples:
- `defineFetchExport(server)` from `package:osrv/runtime/cloudflare.dart`
- `defineFetchExport(server)` from `package:osrv/runtime/vercel.dart`

## Runtime

`Runtime` is the running handle returned by `serve(...)`.

It exposes:
- runtime identity
- capabilities
- optional listener URL
- shutdown controls

Entry-export runtimes do not return a `Runtime`.

## RequestContext

`RequestContext` is the stable per-request context passed to `Server.fetch(...)`.

It gives you:
- `runtime`
- `capabilities`
- `waitUntil(...)`
- typed runtime extension access

## ServerLifecycleContext

`ServerLifecycleContext` is the shared lifecycle context used by:
- `onStart`
- `onStop`
- `onError`

It exposes:
- `runtime`
- `capabilities`
- typed runtime extension access

## RuntimeCapabilities

`RuntimeCapabilities` describes what the active runtime actually supports.

Current fields:
- `streaming`
- `websocket`
- `fileSystem`
- `backgroundTask`
- `rawTcp`
- `nodeCompat`

Capabilities are host truth, not a promise that every runtime behaves the same way.

## RuntimeExtension

`RuntimeExtension` is the marker interface for runtime-specific escape hatches.

Examples:
- `DartRuntimeExtension`
- `NodeRuntimeExtension`
- `BunRuntimeExtension`
- `CloudflareRuntimeExtension<Env, Request>`
- `VercelRuntimeExtension<Request>`

Use runtime extensions for host-specific access that does not belong in the common core API.

## Host Runtime

Host runtime means the real platform `osrv` runs on.

Examples:
- Dart VM
- Node.js
- Bun
- Cloudflare Workers
- Vercel

## Import Rule

For application code, prefer:
- `package:osrv/osrv.dart`
- `package:osrv/runtime/*.dart`

Avoid `package:osrv/src/...` imports.
