# WebSocket Support Spec

Status: draft, partially implemented
Issue: [#17](https://github.com/medz/osrv/issues/17)

## Goal

Add a first-class websocket surface to `osrv` that:

- preserves the existing portable `Server` contract
- keeps runtime selection explicit
- keeps websocket capability reporting honest
- supports route-level websocket ergonomics for downstream frameworks such as `spry`
- uses a shared connected-socket abstraction where that abstraction is real
- does not flatten real host differences into a fake universal runtime shape

## Non-goals

- no router DSL in `osrv`
- no adapter registry
- no fake universal websocket server abstraction
- no promise of websocket parity across all runtime families
- no immediate breaking rewrite of `Server.fetch(...)`
- no platform claims for runtimes that do not actually support websocket servers through the current `osrv` surface

## External Facts To Anchor The Design

From the current repository:

- `Server.fetch(...)` is the shared HTTP path and currently returns `Response`
- `RequestContext` currently exposes runtime metadata, `waitUntil(...)`, and runtime extension access
- `RuntimeCapabilities.websocket` means support through the current `osrv` surface, not host possibility in the abstract
- websocket support is implemented for `dart`, `node`, `bun`, `deno`, and `cloudflare`
- every other runtime family still reports `false`

From local downstream usage:

- `spry` routes everything through one request pipeline
- `spry` route handlers still return `FutureOr<Response>`
- `spry` wants route-level websocket ergonomics without being forced into a second router if possible

From official runtime docs:

- `dart` has direct request-scoped upgrade through `WebSocketTransformer.upgrade(...)`
- `deno` exposes `upgradeWebSocket(request)` as a request-scoped outcome
- `cloudflare` upgrades from fetch using `WebSocketPair` and a `101` response
- `bun` upgrades inside fetch through `server.upgrade(request)`, but websocket lifecycle is server-level
- `node` upgrades through the HTTP server `'upgrade'` event, outside the normal request callback
- `vercel` should remain unsupported for websocket server behavior

These facts mean the public API should be request-scoped and framework-friendly, while the runtime bridges are allowed to differ internally.

## Design Constraints

- keep one portable `Server` contract
- keep `Server.fetch(...)` as the application entrypoint
- do not make websocket acceptance a hidden side effect on `RequestContext`
- represent websocket acceptance as an explicit returned outcome
- let frameworks such as `spry` surface route-level upgrade ergonomics without `src/` imports
- do not flip `capabilities.websocket` to `true` for a runtime until the chosen `osrv` public surface is implemented and documented for that runtime family

## Public API Direction

The preferred design direction is a request-scoped websocket capability exposed from `RequestContext`.

Draft public shape:

```dart
import 'dart:async';

import 'package:ht/ht.dart' show Response;
import 'package:web_socket/web_socket.dart' as ws;

typedef WebSocketHandler = FutureOr<void> Function(ws.WebSocket socket);

base class RequestContext extends ServerLifecycleContext {
  WebSocketRequest? get webSocket;
}

abstract interface class WebSocketRequest {
  /// Whether the current request is a websocket upgrade attempt.
  bool get isUpgradeRequest;

  /// Requested websocket subprotocols from the client handshake.
  List<String> get requestedProtocols;

  /// Returns a response-compatible upgrade outcome to return from `fetch(...)`.
  Response accept(
    WebSocketHandler handler, {
    String? protocol,
  });
}
```

### Important Meaning

`accept(...)` is not an immediate side effect.

It returns an explicit response-compatible upgrade outcome that the active runtime consumes after `fetch(...)` returns.

This preserves:

- one `Server.fetch(...)` application entrypoint
- route-level ergonomics for downstream frameworks
- an explicit returned upgrade outcome instead of hidden context mutation

## Outcome Model

At the public API level, one request can end in one of two user-visible ways:

1. ordinary HTTP response
2. websocket acceptance through `context.webSocket!.accept(...)`

At the runtime level, this maps to three semantic outcomes:

- pass
  - the application did not accept websocket
  - runtime continues normal HTTP handling
- reject
  - the application returned a normal HTTP response to a websocket upgrade attempt
  - runtime sends that HTTP response instead of upgrading
- accept
  - the application returned the upgrade outcome from `accept(...)`
  - runtime performs host-native websocket upgrade

This keeps websocket acceptance explicit without requiring a breaking change to `ServerFetch`.

## Why This Shape

This direction is preferred over a separate `Server.webSocket` surface because:

- downstream frameworks such as `spry` can keep one route tree and one request pipeline
- route params, locals, middleware, and framework-specific handler ergonomics stay request-scoped
- `osrv` remains a runtime layer instead of becoming a websocket router

This direction is preferred over a side-effect API because:

- upgrade remains an explicit returned outcome
- runtimes such as Cloudflare naturally map websocket acceptance to a response outcome
- the request flow remains honest in the docs and the code

This direction is preferred over a full `ServerFetch` signature rewrite because:

- it stays additive
- it avoids immediately breaking every downstream handler type
- it still leaves room for a future explicit union type if the first implementation shows that a `Response`-compatible outcome is too constraining

## Framework Author Guidance

Frameworks should be able to wrap this request-scoped surface into their own route-level UX.

For example, `spry` should be able to expose:

```dart
final response = event.context.webSocket?.accept(
  (socket) async {
    // ...
  },
);

if (response != null) {
  return response;
}

return Response.text('normal http');
```

Or a framework-level helper such as:

```dart
return event.upgradeWebSocket(
  protocol: 'chat',
  (socket) async {
    // ...
  },
);
```

Frameworks may also choose higher-level sugar such as `app.ws(...)`, but that routing UX belongs in the framework, not in `osrv`.

The spec must support these framework needs:

- one route tree
- one param extraction pass
- one request-scoped event/context object
- no requirement to branch on runtime-specific extensions for normal websocket usage

## Middleware, Params, Locals, And Error Handling

Before upgrade is accepted:

- route matching works normally
- framework middleware may run normally
- route params and locals remain available normally
- request-time exceptions may still flow through framework error handlers and `Server.onError`

After upgrade is accepted:

- ordinary HTTP response processing ends for that request
- framework middleware does not re-enter for websocket message events
- framework HTTP error handlers no longer translate errors into HTTP responses
- the websocket session follows websocket-specific lifecycle rules

## Websocket Session Error Model

The spec should define the following baseline behavior:

- if websocket setup throws before the runtime commits the upgrade, the runtime should fail the request through the normal request error path when the host still allows it
- once the upgrade has been committed, HTTP error translation is no longer available
- uncaught websocket session errors should close the websocket with a server-error close code such as `1011`
- uncaught websocket session errors should also surface to the ambient runtime error reporting path

This keeps the request error boundary and the session error boundary explicit.

## Shutdown Semantics

Listener runtimes need explicit websocket shutdown rules.

Baseline requirements:

- `Runtime.close()` stops accepting new HTTP requests and new websocket upgrades
- active websocket sessions become tracked runtime resources, not invisible side effects
- listener runtimes should initiate websocket shutdown with a close code such as `1001` (`going away`)
- `runtime.closed` should not complete until tracked websocket sessions, tracked requests, and tracked `waitUntil(...)` tasks have drained or closed

Entry-export runtimes do not gain a `Runtime`.
For those runtimes, websocket session lifetime remains host-managed after upgrade, and the spec should not invent a fake shared shutdown handle.

## Capability Rules

`RuntimeCapabilities.websocket` must mean:

- `true` only when the current runtime family supports websocket handling through the current public `osrv` surface described by this spec
- `false` when the host may support websockets, but the runtime family has not yet implemented or documented the shared `osrv` surface

This remains stricter than “the host can do websockets somehow.”

## Runtime Family Matrix

Planned interpretation of this spec by runtime family:

| Runtime | Public direction fits? | Initial status | Notes |
| --- | --- | --- | --- |
| `dart` | yes | implemented | direct request-scoped upgrade |
| `node` | yes | implemented | request-scoped public API with internal bridge from Node's `'upgrade'` event |
| `bun` | yes | implemented | request-scoped public API with server-level internal bridge |
| `deno` | yes | implemented | direct request-scoped outcome through Deno's websocket upgrade API |
| `cloudflare` | yes | implemented | request-scoped public API bridged to `WebSocketPair` + `101` outcome |
| `vercel` | no | unsupported | platform limitation |
| `netlify` | not yet | unsupported | keep false until official support path is verified |

## Rollout Plan

### Phase 1

- finalize this spec direction
- implement the first proving runtimes in `dart` and `bun`
- validate route-level ergonomics, upgrade flow, shutdown behavior, and error boundaries

Current state:
- completed for `dart`
- completed for `node`
- completed for `bun`
- completed for `deno`
- completed for `cloudflare`
- still pending for `vercel` and `netlify`

### Phase 2

Add runtimes that naturally reinforce the same request-scoped model:

- none pending in this bucket

### Phase 3

Add runtimes that still need heavier platform validation:

- `netlify` only if a real server-side websocket path becomes available

### Unsupported In Phase 1

- `vercel`
- `netlify`

## Rejected Alternatives

### Separate `Server.webSocket` pipeline

Rejected as the primary public shape because:

- it degrades route-level ergonomics for downstream frameworks such as `spry`
- frameworks would need parallel websocket routing or duplicate route matching
- it weakens the “one request pipeline” authoring model

### Side-effect-only `context.acceptWebSocket()`

Rejected because:

- websocket acceptance must be an explicit returned outcome
- a hidden side effect makes request flow semantics unclear
- it does not map cleanly to runtimes whose natural model is a response outcome

### Runtime-specific-only websocket APIs

Rejected as the end-state design because:

- downstream frameworks would need to branch on runtime families directly
- `RuntimeCapabilities.websocket` would not correspond to a shared `osrv` surface

### Immediate `ServerFetch` breaking rewrite

Rejected for phase 1 because:

- it would force immediate churn on every downstream handler type
- the request-scoped `Response`-compatible outcome should be validated first

## Open Questions

- Should `osrv` re-export selected `package:web_socket` types, or should users continue importing `web_socket` directly?
- Should `WebSocketRequest.accept(...)` support only one selected protocol or a richer negotiation callback?
- Does the first implementation prove that a `Response`-compatible upgrade outcome is sufficient, or do we eventually need a first-class union result type?
- What exact post-upgrade error hook, if any, should `osrv` expose beyond ambient runtime error reporting?

## Current Recommendation

Adopt this request-scoped, explicit-outcome direction as the websocket draft spec.

Do not treat it as frozen public API until real runtime implementations validate:

- upgrade flow
- route-level downstream ergonomics
- shutdown behavior
- websocket session error boundaries
