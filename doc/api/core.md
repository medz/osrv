# osrv Core API

## Goal

This document defines the minimum user-facing core API for `osrv`.

It is intentionally small.
The purpose is to freeze the runtime-facing contract before any implementation detail expands it.

## Design Rules

- center the API on `Server`
- keep input/output aligned with Web `Request` and `Response`
- require explicit host selection
- return one running `Runtime`
- expose runtime truth through `RequestContext`
- avoid framework-shaped APIs such as routing DSLs or middleware stacks

## Minimum Public API

The minimum core API should look conceptually like this:

```dart
typedef ServerFetch = FutureOr<Response> Function(
  Request request,
  RequestContext context,
);

typedef ServerHook = FutureOr<void> Function(ServerLifecycleContext context);

final class Server {
  const Server({
    required this.fetch,
    this.onStart,
    this.onStop,
    this.onError,
  });

  final ServerFetch fetch;
  final ServerHook? onStart;
  final ServerHook? onStop;
  final ServerErrorHook? onError;
}

Future<Runtime> serve(
  Server server,
  RuntimeConfig runtime,
);
```

Some hosts may expose a separate explicit entry API instead of `serve(...)`.

Current examples:

```dart
void main() {
  defineFetchEntry(
    server,
    runtime: FetchEntryRuntime.cloudflare,
  );
}
```

## Server

`Server` is the only required application-facing object in core.

Responsibilities:
- accept requests
- return responses
- participate in lifecycle hooks

Non-responsibilities:
- listening on a socket
- choosing a runtime
- carrying runtime-specific config
- choosing whether a host is serve-based or export-based

## serve

The core serve entry should be explicit and minimal.

```dart
Future<Runtime> serve(
  Server server,
  RuntimeConfig runtime,
);
```

Rules:
- `runtime` is required
- `runtime` is a one-of runtime config input
- `serve(...)` returns one running `Runtime`

Rejected shapes:

```dart
Future<Runtime> serve(Server server);
Future<Runtime> serve(Server server, {String? runtime});
Future<Runtime> serve(Server server, {bool detectRuntime = true});
Future<Runtime> serve(Server server, Runtime runtime);
```

Why `RuntimeConfig` instead of `Runtime` as input:
- input should describe desired host selection
- output should describe active running state
- the same name should not mean both pre-start and post-start concepts

This rule applies only to serve-based hosts.

Entry-export hosts should use a dedicated explicit entry API instead of pretending to return a running runtime.

## RuntimeConfig

The input runtime type should be config-shaped.

Examples:

```dart
final runtime = DartRuntimeConfig(
  host: '0.0.0.0',
  port: 3000,
);

final running = await serve(server, runtime);
```

Rules:
- every runtime family owns its own config type
- config is explicit and one-of
- config must not collapse all platforms into one mega object

Entry-export hosts are outside this specific config model.

## Runtime

`serve(...)` returns the running runtime handle.

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
- `Runtime` is output, not input
- the interface must stay meaningful across all official runtimes
- `url` may be `null` when the host does not expose one
- `close()` must remain defined even if some runtimes treat it as a no-op or conceptual shutdown

## RequestContext

The request context should stay small and runtime-oriented.

```dart
base class RequestContext extends ServerLifecycleContext {
  void waitUntil(Future<void> task);
  T? extension<T extends RuntimeExtension>();
}
```

The context may later include stable request-scoped helpers, but v1 should resist expansion.

Allowed responsibilities:
- expose active runtime identity
- expose runtime capabilities
- expose runtime-specific extensions
- expose background task registration where supported

Forbidden responsibilities:
- store arbitrary mutable app state as product policy
- expose raw host objects directly on the root context
- become a catch-all event object

## RuntimeInfo

The request context and runtime handle need a stable runtime identity object.

```dart
final class RuntimeInfo {
  const RuntimeInfo({
    required this.name,
    required this.kind,
  });

  final String name;
  final String kind;
}
```

Examples:
- `name = "dart"`
- `name = "cloudflare"`
- `kind = "server"`
- `kind = "entry"`

## RuntimeCapabilities

Capabilities expose runtime truth to upper layers.

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

Rules:
- each field must mean real support
- absence means unsupported, not “maybe through polyfill”
- new fields should be added only when at least two runtimes need the distinction

## RuntimeExtension

Runtime-specific features should be exposed through typed extensions.

```dart
abstract interface class RuntimeExtension {
  const RuntimeExtension();
}
```

Access shape:

```dart
final cf = context.extension<
    CloudflareRuntimeExtension<JSObject, web.Request>>();
```

Rules:
- extensions are runtime-specific
- extensions do not belong on root core objects
- missing extension access should return `null` or a typed failure, not fake objects

## Lifecycle Hooks

The minimum lifecycle surface should stay narrow.

```dart
typedef ServerErrorHook = FutureOr<Response?> Function(
  Object error,
  StackTrace stackTrace,
  ServerLifecycleContext context,
);

abstract interface class ServerLifecycleContext {
  RuntimeInfo get runtime;
  RuntimeCapabilities get capabilities;
  T? extension<T extends RuntimeExtension>();
}
```

Lifecycle hooks should support:
- start
- stop
- error interception

Do not add broad hook matrices until real runtimes force the need.

## Error Model

The core should define only a minimal runtime-facing error model.

Initial categories:
- invalid runtime configuration
- unsupported capability usage
- runtime startup failure
- request handling failure

The core should not invent a huge error taxonomy before actual runtimes validate it.

## Anti-Patterns

The following API directions are rejected:

### Router-Centered Core

Rejected:

```dart
final app = App();
app.get('/users', handler);
await app.listen();
```

Reason:
- this makes the product center an application framework, not a server runtime

### Adapter-Centered Core

Rejected:

```dart
await server.listen(adapter: NodeAdapter());
```

Reason:
- runtime selection is a first-class choice, not a replaceable shim

### Ambient Platform Detection

Rejected:

```dart
await serve(server, detectRuntime());
```

Reason:
- runtime selection must stay explicit in product semantics

## Open Constraints for Implementation

When implementing this API:
- preserve `Server` as the center
- keep `RequestContext` narrow
- do not move host-specific state into core
- do not add convenience APIs that hide explicit runtime choice
