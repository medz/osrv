# osrv Capabilities

## Goal

This document freezes the capability model for `osrv`.

`osrv` unifies server shape, not host power.
Capabilities exist so runtime differences stay visible and usable.

## Core Rule

Capabilities describe real runtime support.

They do not describe:
- aspirational support
- polyfilled maybe-support
- marketing equivalence across runtimes

If a runtime cannot support something honestly, that capability must be false.

## Capability Surface

The initial capability surface should stay small.

```dart
final class RuntimeCapabilities {
  const RuntimeCapabilities({
    required this.streaming,
    required this.websocket,
    required this.fileSystem,
    required this.backgroundTask,
    required this.rawTcp,
    required this.nodeCompat,
  });

  final bool streaming;
  final bool websocket;
  final bool fileSystem;
  final bool backgroundTask;
  final bool rawTcp;
  final bool nodeCompat;
}
```

This list can evolve, but only when new fields capture real distinctions needed by more than one runtime family.

## Semantics

### streaming

Meaning:
- the runtime can stream response bodies in a real, supported way

Does not mean:
- buffering everything and pretending it is streaming

### websocket

Meaning:
- the runtime can support websocket handling in its official serving model

Does not mean:
- partial or unofficial hacks that only work in narrow cases

### fileSystem

Meaning:
- the runtime can access a meaningful writable or readable host filesystem in its normal model

Does not mean:
- build-time assets only
- fake in-memory fallbacks presented as host filesystem

### backgroundTask

Meaning:
- the runtime can register work that survives beyond immediate response completion in its supported lifecycle model

Does not mean:
- “maybe the task finishes if the process survives”

### rawTcp

Meaning:
- the runtime can work with raw TCP or equivalent low-level socket control in a meaningful supported way

Does not mean:
- only HTTP-level networking

### nodeCompat

Meaning:
- the runtime has meaningful Node compatibility semantics

Does not mean:
- partial shims that fail under normal Node expectations

## Where Capabilities Live

Capabilities should be visible in two places:
- on the running `Runtime`
- on `RequestContext`

This lets upper layers branch:
- once globally after startup
- per request when needed

## Example

```dart
final runtime = await serve(
  server,
  const NodeRuntimeConfig(
    port: 3000,
  ),
);

if (!runtime.capabilities.backgroundTask) {
  // disable feature globally
}
```

```dart
final server = Server(
  fetch: (request, context) async {
    if (!context.capabilities.websocket) {
      return Response.json(
        {'error': 'websocket unsupported'},
        status: 501,
      );
    }

    return Response.text('ok');
  },
);
```

## Missing Capability Behavior

When a capability is false:
- the runtime should not fake support
- documentation must say so clearly
- the API should fail explicitly where needed

Possible failure forms:
- validation error
- startup failure
- request-time error
- explicit feature disablement by the caller

The correct failure mode depends on when support is required.

## Capability vs Extension

Use capabilities to answer:
- is this class of feature supported?

Use runtime extensions to answer:
- what runtime-specific power is available once support exists?

Example:
- `websocket == true` answers whether websocket is supported at all
- `DartRuntimeExtension` or `CloudflareRuntimeExtension<Env, Request>` answers what host-specific controls exist

Capabilities should stay boolean and coarse.
Extensions can be typed and detailed.

## Design Rules

### Capabilities Must Be Honest

Do not mark a capability as supported unless normal usage can rely on it.

### Capabilities Must Stay Small

Do not turn capabilities into a giant compatibility matrix.

If a distinction matters only inside one runtime family, prefer a runtime extension or runtime-specific docs.

### Capabilities Must Not Replace Documentation

Capabilities are quick truth signals.
They do not remove the need for runtime-specific docs about limits and edge cases.

## Rejected Directions

### Soft Truth

Rejected:

```dart
const RuntimeCapabilities(
  websocket: maybeSupportedInSomeModes,
);
```

Reason:
- callers need reliable branching signals

### Capability Inflation

Rejected:

```dart
const RuntimeCapabilities(
  websocketVersion13: true,
  websocketCompression: false,
  websocketProxySafe: true,
  // ...
);
```

Reason:
- detailed host nuance belongs in docs or extensions, not in the core boolean surface

### Fake Uniformity

Rejected:
- reporting `fileSystem: true` for edge runtimes by inventing synthetic storage semantics
- reporting `backgroundTask: true` for runtimes that only maybe complete post-response work

## Success Criteria

The capability model is correct when:
- upper layers can branch safely
- runtime truth stays visible
- new runtime families can declare support without distorting core
- unsupported features fail honestly instead of silently degrading
