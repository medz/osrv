# osrv Core API

This page documents the stable core API exported by `package:osrv/osrv.dart`.

See [public surface](./public-surface.md) for the full export list.

## Import

```dart
import 'package:osrv/osrv.dart';
```

## Core Request Types

`osrv` re-exports these request primitives from `package:ht/ht.dart`:
- `Headers`
- `Request`
- `Response`

`Server.fetch(...)` always works with these types, regardless of the selected runtime.

## `Server`

`Server` is the main application-facing contract.

```dart
final server = Server(
  fetch: (request, context) async {
    return Response.text('ok');
  },
);
```

### `Server.fetch`

```dart
typedef ServerFetch =
    FutureOr<Response> Function(Request request, RequestContext context);
```

Use `fetch` to handle a request and return a response.

### `Server.onStart`

```dart
typedef ServerHook = FutureOr<void> Function(ServerLifecycleContext context);
```

Runs after a serve-based runtime starts successfully.

### `Server.onStop`

Also a `ServerHook`.

Runs during runtime shutdown.

### `Server.onError`

```dart
typedef ServerErrorHook = FutureOr<Response?> Function(
  Object error,
  StackTrace stackTrace,
  ServerLifecycleContext context,
);
```

Use `onError` to translate request-time failures into a response.

If `onError` returns `null`, the runtime writes a default internal-server-error response.

## Runtime Entry APIs

`package:osrv/osrv.dart` does not export runtime startup functions.

Use runtime-family entrypoints:
- `package:osrv/runtime/dart.dart` exports `serve(Server, {host, port, backlog, shared, v6Only})`
- `package:osrv/runtime/node.dart` exports `serve(Server, {host, port})`
- `package:osrv/runtime/bun.dart` exports `serve(Server, {host, port})`
- `package:osrv/runtime/cloudflare.dart` exports `defineFetchExport(...)` for fetch-export runtimes
- `package:osrv/runtime/vercel.dart` exports `defineFetchExport(...)` for fetch-export runtimes
- `package:osrv/runtime/netlify.dart` exports `defineFetchExport(...)` for fetch-export runtimes

## `Runtime`

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

Meaning:
- `info`: runtime identity such as `dart` or `node`
- `capabilities`: real support flags for the active runtime
- `url`: listener URL when one exists
- `close()`: stop the runtime
- `closed`: completes when shutdown finishes

## `RuntimeInfo`

`RuntimeInfo` identifies the active runtime.

Current values used by official runtimes include:
- `name == 'dart'`
- `name == 'node'`
- `name == 'bun'`
- `name == 'cloudflare'`
- `name == 'vercel'`
- `name == 'netlify'`
- `kind == 'server'` for listener runtimes
- `kind == 'entry'` for fetch-export runtimes

## `RequestContext`

`RequestContext` is passed to every `fetch` call.

It provides:
- `runtime`
- `capabilities`
- `waitUntil(Future<void> task)`
- `extension<T extends RuntimeExtension>()`

Example:

```dart
final server = Server(
  fetch: (request, context) {
    context.waitUntil(Future<void>.value());
    return Response.text(context.runtime.name);
  },
);
```

## `ServerLifecycleContext`

`ServerLifecycleContext` is the base context used by:
- `onStart`
- `onStop`
- `onError`

It gives you:
- `runtime`
- `capabilities`
- `extension<T>()`

## `RuntimeCapabilities`

`RuntimeCapabilities` exposes:
- `streaming`
- `websocket`
- `fileSystem`
- `backgroundTask`
- `rawTcp`
- `nodeCompat`

See [capabilities](../capabilities.md) for the current matrix.

## `RuntimeExtension`

`RuntimeExtension` is the marker interface used for runtime-specific extensions.

Use `context.extension<T>()` to retrieve one.

Examples:
- `DartRuntimeExtension`
- `NodeRuntimeExtension`
- `BunRuntimeExtension`
- `CloudflareRuntimeExtension<Env, Request>`
- `VercelRuntimeExtension<Request>`
- `NetlifyRuntimeExtension<Request>`

## Errors

Core errors exported by `osrv.dart`:
- `RuntimeConfigurationError`
- `RuntimeStartupError`
- `UnsupportedRuntimeCapabilityError`

Typical causes:
- invalid config values
- startup failures
- requesting a capability that a runtime does not expose
