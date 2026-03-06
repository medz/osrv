# osrv Terms

## Purpose

This document freezes the core vocabulary for `osrv`.

The goal is to keep naming drift from returning as implementation evolves.
Every design or code decision should use these terms consistently.

## Primary Terms

### Server

`Server` is the central runtime-facing object in `osrv`.

Meaning:
- the unified request handling shape
- the unit passed into `serve(...)`
- the object upper layers produce when they want to be served by `osrv`

`Server` is not:
- a TCP listener
- a platform process
- a routing framework
- a deployment descriptor

Use `Server` when referring to the portable server contract.

### RuntimeConfig

`RuntimeConfig` is the explicit runtime input passed to `serve(...)`.

Meaning:
- a config shape for one concrete host runtime
- the object that makes runtime selection explicit
- the place where runtime-specific options live

Examples:
- `DartRuntimeConfig`
- `NodeRuntimeConfig`
- `BunRuntimeConfig`

`RuntimeConfig` is not:
- an adapter
- a registry-selected plugin
- the running runtime handle returned after startup

Use `RuntimeConfig` when referring to the user-supplied runtime selection.

### Entry Export

`Entry Export` means an explicit host entry that publishes a server-facing handler without returning a running `Runtime`.

Meaning:
- an explicit deployment entry for hosts that do not use `serve(...)`
- a host-specific export shape owned by one runtime family

Current example:
- `defineFetchEntry(server, runtime: FetchEntryRuntime.cloudflare)`
- `defineFetchEntry(server, runtime: FetchEntryRuntime.vercel)`

`Entry Export` is not:
- automatic runtime detection
- a hidden side effect with ambient globals only
- a running runtime handle

### Runtime

`Runtime` is the running runtime returned by `serve(...)`.

Meaning:
- the runtime-owned handle visible after startup
- the object used for lifecycle observation and shutdown
- the stable runtime identity surface visible to the user

It may expose things like:
- `name`
- `url`
- `close()`
- `closed`

`Runtime` is not:
- a config-only object
- a registry-selected adapter
- a raw platform server object

Use `Runtime` when referring to the live runtime handle after startup.

Do not use `Runtime` for entry-export hosts that do not produce a running handle.

### RequestContext

`RequestContext` is the stable per-request context object provided by `osrv`.

Meaning:
- request-scoped data visible to the `Server`
- runtime metadata available through stable access points
- capability and extension access for the active runtime

`RequestContext` is not:
- an unbounded event bag
- a dump of raw platform objects
- a replacement for runtime-specific extensions

Use `RequestContext` as the common request-level carrier.

### RuntimeCapabilities

`RuntimeCapabilities` describes what the active runtime really supports.

Meaning:
- a stable declaration of support or non-support for key features
- a way for upper layers to branch honestly

Examples:
- `streaming`
- `websocket`
- `fileSystem`
- `backgroundTask`
- `rawTcp`
- `nodeCompat`

`RuntimeCapabilities` is not:
- a promise that behavior is identical across runtimes
- a feature wish list

### RuntimeExtension

`RuntimeExtension` is a runtime-specific extension entry exposed through `osrv`.

Meaning:
- a typed escape hatch for host features that do not belong in core
- a controlled way to expose platform truth

Examples:
- Cloudflare binding access
- Node process or socket access
- Bun host-specific helpers

Use `RuntimeExtension` for runtime-specific power, not for common contracts.

## Secondary Terms

### Core

`Core` means the host-agnostic portion of `osrv`.

It owns:
- stable contracts
- lifecycle vocabulary
- common error semantics
- capability model

It does not own:
- platform APIs
- deployment mechanics
- runtime startup detail

### Host Runtime

`Host Runtime` means the actual execution environment outside `osrv`.

Examples:
- Node.js
- Dart Native (`dart:io`)
- Bun
- Cloudflare Workers
- Vercel

This term refers to the real platform, not the `osrv` handle returned by `serve(...)`.

### Runtime Module

`Runtime Module` means the code directory or namespace that implements one runtime config family and its runtime behavior.

Example meanings:
- `osrv/runtime/dart`
- `osrv/runtime/cloudflare`

Use this term when discussing packaging and module boundaries.

At the current stage, `osrv` defaults to one package with internal directories.
So `Runtime Module` should be read as an internal code boundary first, not as a separate published package.

## Naming Rules

### Use Runtime, Not Adapter

Allowed:
- `runtime`
- `runtime config`

Forbidden:
- `adapter`
- `platform adapter`
- `adapter registry`

Reason:
- runtime selection is a first-class product choice, not a compatibility shim

### Use Config for Input, Runtime for Output

Allowed:
- `DartRuntimeConfig`
- `NodeRuntimeConfig`
- `BunRuntimeConfig`
- `runtime`

Forbidden:
- `DartRuntime` when it really means config input
- `instance` when it really means returned runtime handle
- `target` when it really means runtime selection input

Reason:
- input and output should be named by role, not by historical layering

For entry-export hosts, prefer names that describe the exported behavior directly.

Example:
- `defineFetchEntry`

### Use Capabilities, Not Compatibility

Allowed:
- `capabilities`
- `supported`
- `unsupported`

Avoid:
- “fully compatible”
- “same everywhere”

Reason:
- `osrv` should expose runtime truth, not flatten it rhetorically

### Use Extension for Escapes

Allowed:
- `runtime extension`

Avoid:
- `context.extra`
- `platform bag`
- `misc host data`

Reason:
- host-specific APIs need a named, bounded escape hatch

## Anti-Terms

These terms should not shape the architecture:

### Adapter

Do not use this term in design or code unless discussing a rejected direction.

It implies:
- a hidden center plus pluggable compatibility shells
- runtime selection as incidental wiring

That is not the `osrv` model.

### Universal Config

Do not use this concept as a goal.

It implies:
- all runtimes share one broad option schema
- runtime truth can be reduced to one combined object

That is explicitly rejected.

### Platform Detection

Do not introduce naming around:
- auto detect
- infer runtime
- choose from env

`osrv` requires explicit runtime selection through config input.

## Decision Rules

When introducing a new type or concept, test it against these questions:

1. Does it describe a stable cross-runtime server concept?
2. Is it smaller than a platform abstraction that would hide real differences?
3. Would the same meaning survive across at least two runtime families?
4. Does the name make runtime input and runtime output more explicit, not less?

If the answer is no, it likely belongs in a runtime module, not in core vocabulary.

## Short Glossary

- `Server`: portable server contract
- `RuntimeConfig`: user-supplied runtime input
- `Runtime`: running runtime handle
- `RequestContext`: request-scoped context
- `RuntimeCapabilities`: declared runtime support surface
- `RuntimeExtension`: runtime-specific extension access
- `Core`: host-agnostic `osrv` contract layer
- `Host Runtime`: actual execution platform
