# osrv Final Usage Examples

## Purpose

These examples describe what the final user-facing shape of `osrv` should feel like.

They are not implementation detail.
They are product-shape constraints.

If you want runtime-family docs first, also see:
- [runtime docs](../runtime/README.md)

## Example 1: Node Runtime

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/node.dart';

Future<void> main() async {
  final server = Server(
    fetch: (request, context) async {
      return Response.json({
        'ok': true,
        'runtime': context.runtime.name,
        'path': request.url.path,
      });
    },
  );

  final runtime = await serve(
    server,
    NodeRuntimeConfig(
      host: '0.0.0.0',
      port: 3000,
    ),
  );

  print(runtime.url);
}
```

What this example proves:
- the user builds a `Server`
- the user explicitly picks one runtime config
- the result is a running `Runtime`

## Example 2: Cloudflare Fetch Export

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/esm.dart';
import 'package:web/web.dart' as web;

void main() {
  final server = Server(
    fetch: (request, context) async {
      final cf = context.extension<
          CloudflareRuntimeExtension<Object?, web.Request>>();

      return Response.json({
        'runtime': context.runtime.name,
        'requestUrl': cf?.request?.url,
      });
    },
  );

  defineFetchEntry(
    server,
    runtime: FetchEntryRuntime.cloudflare,
  );
}
```

What this example proves:
- Cloudflare uses an entry export, not `serve(...)`
- runtime-specific data comes from a typed extension
- the same `Server` shape can still run under a different host model

## Example 3: Vercel Fetch Export

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/esm.dart';
import 'package:osrv/runtime/vercel.dart';
import 'package:web/web.dart' as web;

void main() {
  final server = Server(
    fetch: (request, context) async {
      final vercel = context.extension<
          VercelRuntimeExtension<web.Request>>();

      return Response.json({
        'runtime': context.runtime.name,
        'requestUrl': vercel?.request?.url,
        'hasFunctions': vercel?.functions != null,
      });
    },
  );

  defineFetchEntry(
    server,
    runtime: FetchEntryRuntime.vercel,
  );
}
```

What this example proves:
- Vercel is also an entry-export host
- request-specific host helpers stay behind `VercelRuntimeExtension`
- export-entry runtimes do not pretend to be `serve(...) -> Runtime`

## Example 4: Capability-Aware Behavior

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/node.dart';

final runtime = await serve(
  server,
  const NodeRuntimeConfig(
    port: 3000,
  ),
);

if (!runtime.capabilities.websocket) {
  // explicit fallback
}
```

What this example proves:
- capabilities are runtime truth
- unsupported behavior should stay explicit

## Rejected Example 1: Adapter Model

```dart
final server = Server(fetch: handleRequest);
await server.listen(adapter: NodeAdapter());
```

Why it is rejected:
- runtime becomes a replaceable shim
- the product loses explicit runtime semantics

## Rejected Example 2: Auto Detection

```dart
await serve(
  server,
  detectRuntime(),
);
```

Why it is rejected:
- deployment intent becomes ambient behavior
- target choice is hidden from the user

## Rejected Example 3: Framework-Centered Core

```dart
final app = App();
app.get('/', homeHandler);
await app.listen();
```

Why it is rejected:
- the center becomes app composition
- `osrv` drifts into framework territory

## Rejected Example 4: Universal Runtime Config

```dart
final config = OsrvConfig(
  dart: DartRuntimeConfig(port: 3000),
  bun: BunRuntimeConfig(port: 3001),
);
```

Why it is rejected:
- one deployment should not carry multiple runtime contracts
- runtime truth gets flattened into a weak shared object

## Final Shape Summary

The intended final shape for serve-based runtimes is:

```dart
final runtime = await serve(
  someServer,
  SomeExplicitRuntimeConfig(...),
);
```

The intended final shape for Cloudflare is:

```dart
void main() {
  defineFetchEntry(
    someServer,
    runtime: FetchEntryRuntime.cloudflare,
  );
}
```

The intended final shape is not:

```dart
await someApp.listen();
```

And not:

```dart
await runWithAdapter(...);
```
