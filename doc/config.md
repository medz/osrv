# osrv Config Model

## Goal

This document freezes the runtime config model for `osrv`.

The config model must satisfy two goals:
- runtime selection is explicit
- each runtime family owns its own config shape

## Core Rule

The serve entry takes exactly one runtime config input.

Conceptually:

```dart
final runtime = await serve(
  server,
  DartRuntimeConfig(...),
);
```

This means:
- config is not ambient
- config is not registry-resolved
- config is not multi-runtime

## Allowed Shape

Allowed direction:

```dart
final runtime = await serve(
  server,
  NodeRuntimeConfig(
    host: '0.0.0.0',
    port: 3000,
  ),
);
```

The important property is not the concrete syntax.
The important property is that one runtime family is selected by one config object.

## Rejected Shape

Rejected direction:

```dart
final config = OsrvConfig(
  node: NodeRuntimeConfig(port: 3000),
  bun: BunRuntimeConfig(port: 3001),
  cloudflareFetchName: '__osrv_fetch__',
);
```

Reasons:
- one deployment picks one runtime family
- different runtime families have different truths
- a shared mega-object weakens validation and naming

## Runtime Config Families

Each supported host runtime owns one config family.

Expected serve-based families:
- `DartRuntimeConfig`
- `BunRuntimeConfig`
- `NodeRuntimeConfig`

Each family should:
- validate its own fields
- own its own defaults
- document its own constraints

## Design Rules

### One Family Per Config

A config object should select one runtime family only.

Good:
- `DartRuntimeConfig`
- `NodeRuntimeConfig`

Bad:
- `UniversalRuntimeConfig`
- `PlatformConfig`
- `ServerRuntimeOptions` that mixes multiple families

### Config Owns Runtime-Specific Options

Runtime-specific fields belong in runtime-specific config.

Examples:
- `port` and `host` belong in `DartRuntimeConfig`
- `port` and `host` belong in `NodeRuntimeConfig`
- export names belong in `defineFetchEntry(..., name: ...)`

Do not pull such fields upward prematurely.

### Shared Fields Must Earn Promotion

If multiple runtime families later need the same field name and meaning, a shared helper type may be introduced.

But promotion must satisfy both:
- the meaning is genuinely stable
- the field does not erase platform difference

Shared helpers are allowed.
Shared mega-configs are not.

## Validation Rules

Validation should happen as close to the runtime family as possible.

Examples:
- invalid port range for `DartRuntimeConfig`
- invalid port range for `NodeRuntimeConfig`
- invalid export names for `defineFetchEntry(..., name: ...)`

The core should not try to understand every runtime family's validation logic.

## Defaulting Rules

Defaults should remain runtime-family-specific unless they are truly universal.

Examples:
- a default host and port may exist for `dart`
- a default host and port may exist for `node`
- a default export name may exist for `vercel`

Do not invent cross-runtime defaults just for symmetry.

## Config Lifecycle

The config lifecycle is:

```text
user creates RuntimeConfig
  -> serve(server, runtimeConfig)
  -> runtime family validates config
  -> runtime starts
  -> running Runtime is returned
```

This separation matters:
- config means intent
- runtime means active state

## Minimum Examples

### Dart

```dart
final runtime = await serve(
  server,
  DartRuntimeConfig(
    host: '0.0.0.0',
    port: 3000,
    shared: true,
  ),
);
```

### Vercel

```dart
void main() {
  defineFetchEntry(
    server,
    runtime: FetchEntryRuntime.vercel,
  );
}
```

## Rejected Directions

### Runtime Detection

Rejected:

```dart
final runtime = await serve(server, detectRuntimeConfig());
```

Reason:
- runtime choice must be explicit, not ambient

### Runtime As Config Input

Rejected:

```dart
final runtime = DartRuntime(...);
await serve(server, runtime);
```

Reason:
- pre-start config and post-start runtime should not share the same meaning

### Mega Config

Rejected:

```dart
final runtime = await serve(server, AllRuntimeConfig(...));
```

Reason:
- one deployment chooses one runtime family
- each family owns its own truth

## Success Criteria

The config model is correct when:
- runtime choice is obvious at the call site
- each runtime family can validate independently
- the config type name tells the reader this is input, not output
- adding a new runtime family does not require inventing a universal config layer

## Entry-Export Hosts

Some hosts may not use `serve(...)` at all.

Current example:

```dart
void main() {
  defineFetchEntry(
    server,
    runtime: FetchEntryRuntime.cloudflare,
  );
}
```

This does not make `cloudflare` a `RuntimeConfig` family.
It means `cloudflare` currently uses an explicit export-entry shape instead of a running listener handle.
