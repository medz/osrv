# osrv Architecture

## What osrv Is

`osrv` is a unified server runtime shape for Dart applications.

Its job is to provide:
- a single `Server` contract
- explicit host selection
- a stable lifecycle model
- a capability model that exposes platform differences
- a consistent way for upper layers to run on `dart`, `node`, `bun`, `cloudflare`, `vercel`, and future official targets

`osrv` is the runtime substrate, not the application framework.

## What osrv Is Not

`osrv` is not:
- an HTTP framework with its own routing DSL as the product center
- an adapter registry that dynamically picks a platform
- a universal configuration object that contains every platform field at once
- a fake abstraction layer that pretends all runtimes have the same abilities
- a compatibility wrapper around existing code structure

## Product Position

The product stack should be understood like this:

```text
Application / Framework
  -> osrv Server contract
  -> explicit host entry
  -> actual host runtime
```

This means:
- upper layers depend on `osrv`
- `osrv` depends on explicit runtime configs
- runtime implementations depend on real platform APIs

## Documentation Map

Use these documents as the main navigation points:
- [runtime docs](./runtime/README.md) for runtime-family overviews and usage guides
- [final usage examples](./examples/final-usage.md) for user-facing API shape examples
- [runtime API](./api/runtime.md) for `RuntimeConfig` and `Runtime`
- [core API](./api/core.md) for `Server`, `RequestContext`, and serve flow
- [capabilities](./capabilities.md) for capability semantics

## Design Premises

### Explicit Runtime Selection

Each deployment chooses one host family explicitly.

Examples:
- local service on `dart`
- edge deployment on `cloudflare`
- serverless deployment on `vercel`

For serve-based hosts, this choice is expressed through one runtime config.
For entry-export hosts, this choice is expressed through one explicit export API.

The host is not discovered at runtime and is not selected from a registry.

### Single Shape, Uneven Capabilities

`osrv` unifies the server shape, not the platform feature set.

So `osrv` must unify:
- request and response entry semantics
- server lifecycle stages
- runtime capability declaration
- access patterns for runtime-specific extensions

But `osrv` must not pretend that every runtime supports:
- filesystem
- raw sockets
- websocket
- background tasks
- long-lived process state

### Core Before Targets

`osrv core` must stay smaller than any single runtime family implementation.

The core should define only the stable common contract required by more than one runtime family.
Anything that exists only because one host runtime needs it belongs to that target, not to core.

## Layer Model

`osrv` should be split into three conceptual layers.

At the current stage, these are code boundaries inside one package, not separate packages by default.

### 1. Core

The core defines the stable product contract:
- `Server`
- `serve(server, runtimeConfig)` orchestration contract
- `RequestContext`
- lifecycle hooks
- `RuntimeCapabilities`
- `Runtime`
- runtime extension access contract
- shared error semantics

The core must not:
- import host platform libraries
- assume a specific process model
- hardcode deployment behavior

### 2. Runtime Implementations

Each explicit host family maps to one official runtime implementation.

Examples:
- `node`
- `dart`
- `bun`
- `cloudflare`
- `vercel`

Each runtime implementation owns:
- runtime config schema
- startup rules
- request bridging
- response bridging
- capability declaration
- host environment binding
- runtime-specific extension types
- deployment constraints

Not every implementation must use the same top-level API shape.

Examples:
- `dart` and `node` are serve-based runtimes
- `cloudflare` is currently an entry-export runtime

Runtimes are first-class product modules, not community adapters around a hidden center.

### 3. Upper-Layer Integrations

Upper layers should only depend on `osrv` contracts.

They should not:
- import platform APIs directly for normal serving
- guess runtime shape from ambient environment
- rely on hidden side channels outside `osrv` contracts

## Core Responsibilities

The core is responsible for defining:

### Server Contract

The central abstraction is a `Server`.

At minimum, a `Server` must support:
- request handling through a `fetch`-like entry
- optional lifecycle hooks
- access to runtime context through a stable request context object

The center of the API is the server shape, not route configuration.

### Runtime-Oriented Serve Contract

For serve-based hosts, the core should define a uniform way to boot a `Server` using one explicit `RuntimeConfig`.

This means:
- the user constructs one runtime config
- the config selects exactly one runtime shape
- the user calls `serve(server, runtimeConfig)`
- the result is a `Runtime`

This model does not force every host into `serve(...) -> Runtime`.

Current exception:
- `cloudflare` and `vercel` use `defineFetchEntry(...)`

### Capability Model

The core must let upper layers inspect runtime support instead of assuming it.

Capabilities likely include:
- `streaming`
- `websocket`
- `fileSystem`
- `backgroundTask`
- `nodeCompat`
- `rawTcp`

This list can evolve, but every capability must describe real host behavior, not marketing equivalence.

### Extension Model

The core must provide a controlled way to access runtime-specific features without polluting common contracts.

Examples:
- Cloudflare request metadata
- Node process or socket details
- Bun-specific websocket or file helpers

These features should live behind runtime-specific extension entry points.

## Runtime Responsibilities

Each runtime implementation is responsible for host truth.

That includes:
- what startup means
- what shutdown means
- whether there is a durable server instance
- whether request-scoped background work exists
- what host bindings are available
- what cannot be supported

If a runtime cannot support a capability, it must declare that clearly instead of emulating it badly.

## Configuration Model

Configuration is host-first.

For serve-based hosts, runtime selection should stay explicit at the `serve(...)`
call site instead of being hidden behind a synthetic top-level config bag.

Correct direction:

```dart
final runtime = await serve(
  server,
  const DartRuntimeConfig(
    host: '127.0.0.1',
    port: 3000,
  ),
);
```

Incorrect direction:

```text
OsrvConfig
  node: ...
  bun: ...
  cloudflare: ...
  vercel: ...
```

The reason is product semantics:
- one deployment chooses one target
- each target has its own contract
- shared defaults should be extracted only after they prove stable

Entry-export hosts may not use `RuntimeConfig` at all.

Current example:

```dart
final runtime = await serve(
  server,
  const DartRuntimeConfig(port: 3000),
);
```

## Lifecycle Model

The lifecycle should be unified conceptually, but not forced into identical host mechanics.

The stable lifecycle vocabulary should cover:
- configuration resolved
- runtime prepared
- server started
- request handled
- server stopping
- server stopped

Different targets may realize these stages differently.
For example, an edge runtime may not look like a long-lived process, but it still participates in the same conceptual lifecycle.

## Architectural Constraints

The following constraints are mandatory:

### No Adapter Registry

There must be no core structure like:
- `Adapter`
- `AdapterRegistry`
- `detectPlatform()`
- `pickRuntimeFromEnv()`

Those patterns hide a product decision that should stay explicit.

### No Fake Uniformity

Do not add broad abstractions just to erase visible runtime differences.

Bad examples:
- a fake shared filesystem API in core
- a mandatory websocket contract for every runtime
- a single server state model that assumes long-lived processes everywhere

### No Framework Capture

`osrv` cannot become an application framework by accident.

If a feature mainly serves routing, controllers, middleware chains, or app composition, it belongs above `osrv` unless it is required to define the server runtime shape itself.

## Initial Implementation Strategy

Implementation should follow this order:

1. Freeze terms and architecture.
2. Freeze minimum user-facing API.
3. Freeze runtime config model.
4. Freeze capability model.
5. Build `core`.
6. Build one runtime family as proof, preferably `dart`.
7. Expand to other targets one by one.

This order matters because runtime families should validate the core contract, not shape it accidentally through premature implementation detail.

## Success Criteria

The architecture is successful when:
- a user can declare one explicit runtime config cleanly
- upper layers can run through a stable `Server` contract
- runtime differences are inspectable and honest
- adding a second runtime family does not require an adapter rewrite
- the core remains small while targets stay authoritative
