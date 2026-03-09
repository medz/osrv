# osrv Runtime API

This page documents how runtime selection works in the public API.

See [public surface](./public-surface.md) for the importable entrypoints.

## Runtime Families

`osrv` currently ships five official runtime families:
- `dart`
- `node`
- `bun`
- `cloudflare`
- `vercel`

## The Two Runtime Models

### Serve-Based

These runtimes use runtime-specific `serve(server, {platform params})`:
- `dart`
- `node`
- `bun`

They return a running `Runtime` handle.

### Entry-Export

These runtimes use runtime-specific `defineFetchExport(server)`:
- `cloudflare`
- `vercel`

They do not return a running `Runtime`.

## Serve Parameters

For serve-based runtimes, runtime choice is expressed through the selected runtime entrypoint and its named platform parameters.

Example:

```dart
final runtime = await serve(
  server,
  host: '127.0.0.1',
  port: 3000,
);
```

## Running Runtime Output

Serve-based runtimes return:

```dart
abstract interface class Runtime {
  RuntimeInfo get info;
  RuntimeCapabilities get capabilities;
  Uri? get url;
  Future<void> close();
  Future<void> get closed;
}
```

This is the post-start runtime handle.

It is not:
- a config object
- a wrapper around every host-native object
- the API used by Cloudflare or Vercel entry exports

## Entry Export API

For Cloudflare and Vercel:

```dart
defineFetchExport(
  server,
);
```

Optional:

```dart
defineFetchExport(
  server,
  name: '__custom_fetch__',
);
```

This defines a JavaScript fetch export through the selected runtime family entrypoint.

## Runtime-Specific Extensions

Runtime-specific power is exposed through context extensions, not through the `Runtime` handle.

Current public runtime-specific types:
- `DartRuntimeExtension`
- `NodeRuntimeExtension`
- `BunRuntimeExtension`
- `CloudflareRuntimeExtension<Env, Request>`
- `CloudflareExecutionContext`
- `VercelRuntimeExtension<Request>`
- `VercelFunctions`
- `VercelRuntimeCache`

## Current Entry Summary

| Runtime | Import | Entry model | Returns `Runtime` |
| --- | --- | --- | --- |
| `dart` | `package:osrv/runtime/dart.dart` | `serve(...)` | yes |
| `node` | `package:osrv/runtime/node.dart` | `serve(...)` | yes |
| `bun` | `package:osrv/runtime/bun.dart` | `serve(...)` | yes |
| `cloudflare` | `package:osrv/runtime/cloudflare.dart` | `defineFetchExport(...)` | no |
| `vercel` | `package:osrv/runtime/vercel.dart` | `defineFetchExport(...)` | no |

## Errors You Should Expect

Typical runtime-related failures:
- `RuntimeConfigurationError` for invalid serve config values
- `RuntimeStartupError` for listener startup failures
- compile-time target errors when a JavaScript-only runtime entrypoint is built for a native target
- `UnsupportedError` when a JavaScript-target build runs on a host that does not expose the required runtime APIs

Examples:
- compiling `package:osrv/runtime/node.dart` or `package:osrv/runtime/cloudflare.dart` into a native executable
- `serve(server, host: ..., port: ...)` from `package:osrv/runtime/node.dart` on a JavaScript host without Node APIs
- `serve(server, host: ..., port: ...)` from `package:osrv/runtime/bun.dart` on a JavaScript host outside Bun
