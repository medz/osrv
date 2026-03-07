# Node Host Model

## Purpose

This document defines the intended host model for the future `node` runtime family.

The goal is to answer one architectural question clearly:

What should `osrv` use for Node.js host interop in Dart?

## Baseline

`node` is not another `dart:io` runtime.

It is a JavaScript-host runtime family.
That means the implementation direction should be:

- use Dart's modern JS interop stack for Node-specific APIs
- use `package:web` only for standard Web APIs exposed by the JS host
- keep `ht` as the cross-runtime HTTP model inside `osrv`

Official references:
- Dart JS interop hub: [dart.dev/interop/js-interop](https://dart.dev/interop/js-interop)
- JS interop usage guide: [dart.dev/interop/js-interop/usage](https://dart.dev/interop/js-interop/usage)
- Getting started with JS interop: [dart.dev/interop/js-interop/start](https://dart.dev/interop/js-interop/start)
- `package:web` migration guide: [dart.dev/interop/js-interop/package-web](https://dart.dev/interop/js-interop/package-web)
- `dart:js_interop` API reference: [api.dart.dev/dart-js_interop](https://api.dart.dev/stable/latest/dart-js_interop/index.html)
- `dart:js` API reference: [api.dart.dev/dart-js](https://api.dart.dev/dart-js/)
- `dart:js_util` API reference: [api.dart.dev/dart-js_util](https://api.dart.dev/dart-js_util/)

## Interop Stack

The intended stack for `node` should be:

```text
osrv core
  -> ht Request / Response
  -> node runtime implementation
     -> package:web for standard Web APIs when available
     -> dart:js_interop for Node-specific APIs
     -> dart:js_interop_unsafe only when static interop is insufficient
```

## Why This Stack

### 1. `dart:js_interop` Is the Primary JS Interop Layer

For modern Dart JS interop, the baseline should be `dart:js_interop`.

Reason:
- it is the recommended replacement for older JS interop approaches
- it works with the current interop direction in Dart
- it keeps the runtime model explicit and typed

Practical consequence:
- do not base new `node` work on `dart:js`, `dart:js_util`, or `package:js`
- those are legacy paths and should not shape new architecture

### 2. `package:web` Is for Standard Web APIs, Not Node-Specific Host APIs

`package:web` should be used where the Node.js runtime exposes standard Web APIs that match browser-style platform contracts.

Examples:
- `Request`
- `Response`
- `Headers`
- `URL`
- `ReadableStream`
- `AbortController`

But `package:web` should not be treated as a Node host API layer.

Examples that still require Node-specific interop:
- `process`
- `http`
- `net`
- server listen/close behavior
- Node stream or socket objects not modeled as standard Web APIs

### 3. `ht` Stays the Internal Cross-Runtime HTTP Type Layer

Inside `osrv`, the portable server contract should continue to use `ht`.

Reason:
- `ht` is already the cross-runtime request/response model in this codebase
- the runtime boundary should bridge host objects into `ht`, not leak host types upward

So for `node`, the intended flow is:

```text
Node host object
  -> JS interop / package:web view
  -> bridge into ht.Request
  -> Server.fetch
  -> ht.Response
  -> bridge back to Node host response
```

## Layer Split

The future `node` runtime should be split conceptually like this:

### Standard Web Surface

Use `package:web` when the host already exposes a standard Web API that matches `osrv` needs.

Candidate areas:
- fetch request/response objects
- web headers
- web streams
- URL parsing

### Node Host Surface

Use `dart:js_interop` for APIs that are genuinely Node-specific.

Candidate areas:
- server startup
- listen/close lifecycle
- process bindings
- raw TCP and upgrade hooks
- Node-specific event emitters or callback APIs

### Unsafe Escape Surface

Use `dart:js_interop_unsafe` only for:
- dynamic property access
- cases where a stable static interop declaration is not practical yet
- temporary bridge gaps during early implementation

This should be treated as the narrowest layer, not the default.

## Design Rules

### Rule 1: Never Build Node on Legacy JS Interop

Do not introduce:
- `dart:js`
- `dart:js_util`
- `package:js`

for new `node` runtime architecture.

### Rule 2: Never Treat `package:web` as the Node Runtime

`package:web` can cover standard APIs that Node exposes.
It does not replace a real Node host model.

### Rule 3: Keep Host Types Below the Bridge

`Server.fetch` should still see:
- `ht.Request`
- `RequestContext`

not:
- JS interop objects
- `package:web` objects
- raw Node host values

### Rule 4: Node Capability Claims Must Follow Real Host Wiring

Do not mark a capability as supported until the Node host path actually provides it.

In particular:
- `websocket`
- `streaming`
- `rawTcp`
- `backgroundTask`

must follow real implementation, not expectation.

## Current Scope

The current `node` runtime intentionally focuses on:

1. `NodeRuntimeConfig`
2. minimal Node interop bindings for startup and shutdown
3. request bridging into `ht.Request`
4. response bridging back to `ServerResponse`
5. a narrow `NodeRuntimeExtension`

Not in the current scope:
- websocket
- full process integration
- advanced stream adapters
- broad Node module coverage

## Non-Goals

This host model does not assume:
- browser-only APIs
- a fake universal JS runtime abstraction
- that all JS runtimes expose the same host surface

`node`, `cloudflare`, and `vercel` may all be JavaScript-host runtimes, but they should still be implemented as separate runtime families.
