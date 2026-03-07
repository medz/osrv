# osrv Public Surface

This page lists the stable package entrypoints and exports intended for application code.

## Importable Entry Points

These are the supported public import paths:
- `package:osrv/osrv.dart`
- `package:osrv/esm.dart`
- `package:osrv/runtime/dart.dart`
- `package:osrv/runtime/node.dart`
- `package:osrv/runtime/bun.dart`
- `package:osrv/runtime/cloudflare.dart`
- `package:osrv/runtime/vercel.dart`

Everything under `package:osrv/src/...` is implementation detail unless it is re-exported through one of the entrypoints above.

## `package:osrv/osrv.dart`

Stable exports:

```dart
Headers
Request
Response

RuntimeCapabilities
RuntimeConfigurationError
RuntimeStartupError
UnsupportedRuntimeCapabilityError
RuntimeExtension
RequestContext
ServerLifecycleContext
Runtime
RuntimeInfo
RuntimeConfig
serve
Server
ServerFetch
ServerHook
ServerErrorHook
```

## `package:osrv/esm.dart`

Stable exports:

```dart
defaultFetchEntryName
defineFetchEntry
FetchEntryRuntime
```

Use this entrypoint only for fetch-export runtimes.

## Runtime Family Entrypoints

### `package:osrv/runtime/dart.dart`

```dart
DartRuntimeConfig
DartRuntimeExtension
```

### `package:osrv/runtime/node.dart`

```dart
NodeRuntimeConfig
NodeRuntimeExtension
```

### `package:osrv/runtime/bun.dart`

```dart
BunRuntimeConfig
BunRuntimeExtension
```

### `package:osrv/runtime/cloudflare.dart`

```dart
CloudflareRuntimeExtension
CloudflareExecutionContext
cloudflareWaitUntil
```

### `package:osrv/runtime/vercel.dart`

```dart
VercelRuntimeExtension
VercelFunctions
VercelRuntimeCache
```

## What Not To Import

Do not build application code against:
- `package:osrv/src/core/...`
- `package:osrv/src/runtime/...`
- JS interop files
- request/response bridge files
- preflight or probe helpers
- runtime host implementation files

Those files are intentionally allowed to change faster than the public package contract.

## Recommended Usage

Serve-based:

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/node.dart';

Future<void> main() async {
  final runtime = await serve(
    server,
    const NodeRuntimeConfig(host: '127.0.0.1', port: 3000),
  );

  print(runtime.url);
}
```

Entry-export:

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/esm.dart';

void main() {
  defineFetchEntry(
    server,
    runtime: FetchEntryRuntime.cloudflare,
  );
}
```
