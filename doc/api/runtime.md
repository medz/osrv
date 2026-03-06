# osrv Runtime API

## Goal

This document defines the minimum contract for:
- runtime config input
- running runtime output

The purpose is to keep input and output distinct:
- config selects the host
- runtime represents the active running state

## Concept

The user-facing flow should be:

```dart
final server = Server(...);
final runtime = await serve(server, DartRuntimeConfig(...));
```

This means:
- the user supplies `Server`
- the user supplies one `RuntimeConfig`
- `serve(...)` returns one `Runtime`

## RuntimeConfig Families

Each supported host runtime owns one config family.

Examples:
- `DartRuntimeConfig`
- `BunRuntimeConfig`
- `NodeRuntimeConfig`

Rules:
- config families are explicit
- config families are one-of
- config families must not be collapsed into one universal runtime config object

## Preferred Config Shape

The config should be data-shaped and host-specific.

Example:

```dart
final class DartRuntimeConfig implements RuntimeConfig {
  const DartRuntimeConfig({
    required this.host,
    required this.port,
    this.backlog = 0,
    this.shared = false,
    this.v6Only = false,
  });

  final String host;
  final int port;
  final int backlog;
  final bool shared;
  final bool v6Only;
}
```

Preferred rule:
- if the type is passed into `serve(...)`, call it `*RuntimeConfig`
- do not call config inputs `*Runtime`

## Runtime

`Runtime` is the running handle returned by `serve(...)`.

The conceptual shape should look like this:

```dart
abstract interface class Runtime {
  RuntimeInfo get info;
  RuntimeCapabilities get capabilities;
  Uri? get url;
  Future<void> close();
  Future<void> get closed;
}
```

Rules:
- `Runtime` is output only
- `Runtime` must stay meaningful across all official runtimes
- `url` may be `null` for runtimes that do not expose an externally meaningful listener URL
- `close()` must exist even if the underlying host treats shutdown differently
- runtimes that are export-entry-only are outside this `Runtime` handle model

## Runtime Responsibilities

The running runtime handle is responsible for exposing:
- runtime identity
- capability truth
- lifecycle termination
- optional runtime URL

The running runtime handle is not responsible for:
- carrying raw target config back to the user as its main identity
- becoming a direct wrapper of every host-native object
- flattening away host differences

## Relationship Between Config and Runtime

The mapping for serve-based runtimes is:

```text
RuntimeConfig + Server
  -> serve(...)
  -> Runtime
```

The same host family has two distinct concepts:
- `DartRuntimeConfig`: pre-start input
- running `Runtime` whose `info.name == "dart"`: post-start output

This split keeps the API readable:
- config means intent
- runtime means active state

## Capability Declaration

Capabilities are attached to the running runtime and request context, not to the config input.

Example:

```dart
final runtime = await serve(server, DartRuntimeConfig(...));

if (runtime.capabilities.websocket) {
  // ...
}
```

Rules:
- capabilities must reflect host reality
- unsupported means unsupported
- config should not pretend to imply capability truth by name alone

## Runtime Extension Access

Runtime-specific power should stay behind extensions surfaced through request or lifecycle context.

Examples:
- Cloudflare env / request / execution context
- Node process or socket details
- Bun host-specific objects

The running runtime handle itself should stay narrow.

## Host Truth Rules

The runtime system is required to preserve host truth.

Examples:
- if the host has no writable filesystem, do not emulate one in core
- if the host has no durable listener URL, do not invent one
- if websocket support is partial, expose that through capabilities and docs

## Rejected Designs

### Config-As-Runtime

Rejected:

```dart
final runtime = DartRuntime(
  host: '0.0.0.0',
  port: 3000,
);

await runtime.serve(server);
```

Reason:
- input and output collapse into one term
- the API becomes less explicit about pre-start versus post-start state

### Registry-Driven Runtime Resolution

Rejected:

```dart
final runtime = RuntimeRegistry.current.pick();
await serve(server, runtime);
```

Reason:
- hides product intent
- makes runtime choice incidental

### All-Runtimes Config Object

Rejected:

```dart
final runtime = UniversalRuntimeConfig(
  nodePort: 3000,
  cloudflareBindings: ...,
);
```

Reason:
- one deployment selects one runtime family
- one runtime family owns one config model

## Documentation Requirements Per Runtime Family

Every runtime family should eventually ship with:
- a runtime overview
- capability table
- config reference
- lifecycle notes
- extension reference
- known constraints

No runtime family should be considered complete with code alone.

## Minimum Runtime Families

The current expected official runtime families are:
- `dart`
- `node`
- `bun`
- `cloudflare`
- `vercel`

The implementation order can be incremental, but the contract should be designed so these families fit without inventing an adapter layer later.
Some official hosts may use a different explicit entry shape.

Current example:

```dart
void main() {
  defineFetchEntry(
    server,
    runtime: FetchEntryRuntime.cloudflare,
  );
}
```

That is still explicit host selection, but it is not a running listener runtime.
