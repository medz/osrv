# Deno Runtime Family Spec

Status: draft
Issue: [#15](https://github.com/medz/osrv/issues/15)

## Goal

Add a first-class `deno` serve-based runtime family to `osrv` that:

- preserves the existing portable `Server` contract
- keeps runtime selection explicit through `package:osrv/runtime/deno.dart`
- uses Deno-native serving APIs for the hot path
- exposes Deno-specific access through a typed `DenoRuntimeExtension`
- reports Deno capabilities honestly instead of inheriting Node or Bun behavior

## Non-goals

- no `detectPlatform()`
- no adapter registry
- no merged cross-runtime config object
- no fake websocket support
- no Deno Deploy or edge/export model in this runtime family
- no implementation that routes normal serving through Node `http` compatibility just because Deno can import `node:*`

## External Facts To Anchor The Design

From official Deno docs:

- `Deno.serve(...)` returns `Deno.HttpServer`, which exposes `addr`, `finished`, and `shutdown()` for listener lifecycle control
- `Deno.serve(...)` supports `hostname` and `port` options for TCP listening
- Deno blocks network listeners unless network access is granted, typically with `--allow-net`
- Deno has meaningful Node compatibility, including `node:` built-in modules and a `process` global, but that does not make Deno the `node` runtime family

From the current repository:

- serve-based runtimes return `Runtime` and use `onStart`, `onStop`, `onError`, and `RequestContext.waitUntil(...)`
- Bun already uses the Web `Request`/`Response` model directly and reuses the shared JS response bridge
- Node uses a different transport bridge because `node:http` is not Web-native, so Deno must not copy Node’s request and response bridge shape unless Deno itself forces that complexity
- the public runtime entrypoint pattern is `lib/runtime/<name>.dart` exporting one extension type and one `serve(...)`

## Public API

Add a new public entrypoint:

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/deno.dart';

final runtime = await serve(
  server,
  host: '127.0.0.1',
  port: 3000,
);
```

Public exports from `package:osrv/runtime/deno.dart`:

- `DenoRuntimeExtension`
- `serve`

Public `serve(...)` shape:

```dart
Future<Runtime> serve(
  Server server, {
  String host = '127.0.0.1',
  int port = 3000,
})
```

Validation:

- `host` must not be empty after trimming
- `port` must be between `0` and `65535`

Compatibility rule:

- this change must stay additive and source-compatible for all existing entrypoints

## Runtime Identity And Capabilities

Runtime identity:

- `info.name == 'deno'`
- `info.kind == 'server'`

Capability matrix for `deno`:

| Capability | Value | Rationale |
| --- | --- | --- |
| `streaming` | `true` | Deno serves Web `Response` streams natively |
| `websocket` | `false` | `osrv` websocket surface is still not implemented |
| `fileSystem` | `true` | Deno has real filesystem APIs, subject to permissions |
| `backgroundTask` | `true` | `osrv` can track `waitUntil(...)` work during shutdown |
| `rawTcp` | `true` | Deno exposes meaningful low-level network APIs |
| `nodeCompat` | `true` | Deno exposes meaningful Node-compatible APIs, but remains a separate runtime family |

`nodeCompat` being `true` must be documented carefully:

- it means Deno provides meaningful Node compatibility
- it does not mean Deno should serve requests through Node `http`
- it does not imply parity with Node-specific lifecycle or transport behavior

## Host Requirements

The `deno` runtime requires:

- a JavaScript-target build
- a JavaScript host
- the global `Deno` object
- `Deno.serve`
- permission to open the requested network listener

Host notes:

- compiling `package:osrv/runtime/deno.dart` to a native executable must fail
- compiling to JavaScript is necessary but not sufficient
- startup on a non-Deno JavaScript host must fail explicitly with `UnsupportedError`
- startup on Deno without listener permission should surface as `RuntimeStartupError`
- this runtime targets the Deno CLI listener model, not Deno Deploy

## Runtime Extension

Add `DenoRuntimeExtension` with the same lifecycle/request split used by the other serve-based runtimes.

Proposed public shape:

```dart
final class DenoRuntimeExtension implements RuntimeExtension {
  const DenoRuntimeExtension({
    this.deno,
    this.server,
    this.request,
  });

  final DenoGlobal? deno;
  final DenoHttpServerHost? server;
  final DenoRequestHost? request;

  factory DenoRuntimeExtension.host();
}
```

Extension semantics:

- `deno` is present on real Deno hosts
- `server` is present in lifecycle hooks after binding succeeds
- `request` is present only for active request handling
- `request` should stay a zero-logic Deno host marker, not a second request bridge

## Implementation Shape

Add a new internal runtime directory:

- `lib/src/runtime/deno/extension.dart`
- `lib/src/runtime/deno/interop.dart`
- `lib/src/runtime/deno/probe.dart`
- `lib/src/runtime/deno/preflight.dart`
- `lib/src/runtime/deno/public.dart`
- `lib/src/runtime/deno/serve.dart`
- `lib/src/runtime/deno/serve_host.dart`
- `lib/src/runtime/deno/request_host.dart`

Add a new public entrypoint:

- `lib/runtime/deno.dart`

## Interop Design

Use modern Dart JS interop patterns already present in this repository:

- `dart:js_interop`
- interop extension types
- `package:web` for Web request and response objects
- `JSPromise<T>.toDart` for async host interop

Interop requirements:

- model `DenoServeTcpOptions` as a typed object-literal interop type
- model `DenoGlobal.serve`, `DenoGlobal.version`, `DenoHttpServerHost.addr`, `DenoHttpServerHost.finished`, and `DenoHttpServerHost.shutdown()` as typed interop members
- keep the request handler boundary typed as `web.Request -> JSPromise<web.Response>` or an equivalent typed JS callback form
- use `dart:js_interop_unsafe` only as a single documented exception if one specific host detail cannot be represented cleanly with typed interop

Unsafe interop is not expected for the normal Deno serving path.

Expected interop surface:

- `DenoGlobal`
- `DenoVersion`
- `DenoHttpServerHost`
- `DenoServeTcpOptions`
- `DenoNetAddr`

Likely members:

- `DenoGlobal.version`
- `DenoGlobal.serve`
- `DenoHttpServerHost.addr`
- `DenoHttpServerHost.finished`
- `DenoHttpServerHost.shutdown()`

Avoid:

- broad `dart:js_interop_unsafe` usage
- `dart:js_util`
- legacy `package:js`
- dynamic dispatch over host objects
- untyped `JSAny` plumbing when a concrete interop type is available

## Request And Response Bridging

Deno should use the Web bridge path, not the Node transport bridge path.

Request flow:

- accept the incoming `web.Request` from `Deno.serve(...)`
- construct the `ht.Request` directly as `Request(request)`
- store a zero-logic `DenoRequestHost` view in `DenoRuntimeExtension.request`

Response flow:

- reuse `lib/src/runtime/_internal/js/web_response_bridge.dart`
- return the resulting `web.Response` directly to Deno

This intentionally avoids adding a Deno-specific request bridge file unless a real Deno-only behavior requires one.
`request_host.dart` is allowed only as a zero-logic marker around the raw Deno request object for extension access.

## Lifecycle Model

`serveDenoRuntimeHost(...)` should follow the existing serve-based lifecycle contract:

1. run preflight validation
2. bind the Deno server
3. create lifecycle context with `DenoRuntimeExtension(deno: ..., server: ...)`
4. invoke `server.onStart`
5. handle requests through `server.fetch`
6. on `close()`, stop accepting new requests, invoke `server.onStop`, then drain tracked requests and `waitUntil(...)` tasks

Startup sequencing must match Node and Bun semantics:

- requests arriving before `onStart` completes must wait on startup
- if `onStart` fails, startup should abort and serving should not continue normally

Shutdown semantics:

- use Deno server shutdown for listener closure
- continue using `ShutdownCoordinator` for in-flight requests and `waitUntil(...)` tasks
- keep the same shutdown order as the existing serve runtimes: close listener, invoke `onStop`, then drain tracked requests and tasks through `ShutdownCoordinator`
- `Runtime.closed` should complete only after listener shutdown, `onStop`, request draining, and tracked background work

Runtime URL:

- derive the URL from the bound server address
- when port `0` is used, read the actual bound port from `server.addr`

## Error Handling

Config-time errors:

- empty `host`
- invalid `port`

Preflight errors:

- non-JavaScript host
- JavaScript host without global `Deno`
- Deno host without `Deno.serve`

Startup errors:

- listener bind failure
- permission-denied listener startup
- `onStart` failure

Request errors:

- route through the shared `handleServerError(...)` flow
- preserve `server.onError` semantics

## Deno And Node Compatibility Strategy

The serving path should stay Deno-native for performance and minimal boilerplate.

The compatibility strategy is narrower:

- recognize Deno as `nodeCompat: true`
- document that Deno can run code using Node-compatible APIs where Deno actually supports them
- do not pull the `node` runtime implementation into the Deno serving hot path
- do not add compatibility shims that only forward one host object into another without reducing real duplication

This keeps the runtime honest:

- Deno serves like Deno
- Node serves like Node
- shared behavior lives only in contracts or genuinely shared bridge code

## Bad-Code Guardrails

The implementation should reject the following patterns:

- empty forwarding layers that add no behavior, no validation, and no API stability value
- Deno request snapshot or response bridge code that duplicates existing Web request and response support
- a `request_host.dart` file that grows beyond a zero-logic host marker for extension access
- generic “JS serve runtime” abstractions unless they remove real duplicated lifecycle code across Bun and Deno without flattening host differences
- hidden fallback to Node transport serving
- capability constants copied from another runtime without runtime-specific rationale

Preferred style:

- small typed interop surfaces
- direct use of `Request(request)` and `webResponseFromHtResponse(...)`
- one clear preflight type and one clear host-serving path
- extension types instead of wrapper classes
- typed object-literal interop instead of unsafe property bags on the normal serving path

## Documentation Updates Required

At minimum update:

- `doc/architecture.md`
- `doc/config.md`
- `doc/capabilities.md`
- `doc/terms.md`
- `doc/runtime/README.md`
- `doc/runtime/deno.md`
- `doc/api/runtime.md`
- `doc/api/public-surface.md`
- `doc/examples/final-usage.md`
- `example/README.md`

Documentation content must cover:

- what the Deno runtime is
- what it is not
- host requirements
- capability values and their rationale
- lifecycle behavior
- permission expectations
- minimal bootstrap example
- one explicit counterexample showing when `deno` is the wrong runtime family
- current limitations

## Example Updates Required

Add:

- `example/deno.dart`

The example should mirror the existing `node.dart` and `bun.dart` examples:

- import `package:osrv/runtime/deno.dart`
- call `serve(example.server)`
- print the bound runtime URL
- await `runtime.closed`

## Test Plan

Add focused tests before implementation:

- `integration_test/deno/preflight_test.dart`
- `integration_test/deno/runtime_process_test.dart`
- `integration_test/deno/app/server.dart`

Extend existing compile coverage:

- `integration_test/compile/fetch_export_compile_test.dart`

### Preflight Tests

Cover:

- host trimming and parameter validation
- explicit block reason when Deno globals are unavailable
- positive preflight when an injected Deno probe reports `Deno.serve`

### Process Test

Follow the Bun process-test shape:

- compile a Deno fixture with `dart compile js`
- run it under Deno CLI with `--allow-net`
- verify runtime identity and bound URL
- verify the exact `RuntimeCapabilities` row for `deno`
- verify request bridging for method, headers, query, and body
- verify streaming response behavior
- verify `onError` translation
- verify `waitUntil(...)` work delays final shutdown
- verify `DenoRuntimeExtension.deno` and `.server` are present in lifecycle hooks
- verify `DenoRuntimeExtension.request` is present during requests

### Compile Tests

Add assertions that:

- `example/deno.dart` does not compile to a native executable
- the Deno serve bundle does not pull in Node or Bun serving code
- the Node and Bun serve bundles do not pull in Deno runtime code

The compile isolation expectation is specifically:

- no `serveNodeRuntime`
- no `node:http`
- no Bun host startup strings

## Red-Green Plan

1. add tests and the fixture first
2. run the Deno-focused test set and expect failure
3. implement the runtime and doc/example updates
4. rerun the Deno-focused test set to green
5. run the full repository test suite
6. run format and analysis

## Local Environment Note

Current local environment does not have `deno` on `PATH`.

That affects only the process-test execution phase.
It does not change the public design or test matrix, but implementation work must either:

- install Deno locally for verification, or
- stop before green verification and report the missing host runtime

## Research Links

- [Deno.serve](https://docs.deno.com/api/deno/~/Deno.serve)
- [Deno.HttpServer](https://docs.deno.com/api/deno/~/Deno.HttpServer)
- [Deno.version](https://docs.deno.com/api/deno/~/Deno.version)
- [Deno Node and npm compatibility](https://docs.deno.com/runtime/fundamentals/node/)
- [Deno security and permissions](https://docs.deno.com/runtime/fundamentals/security/)
- [Dart JS interop usage](https://dart.dev/interop/js-interop/usage)
- [Dart JS types](https://dart.dev/interop/js-interop/js-types)
