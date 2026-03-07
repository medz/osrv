# osrv Config

Runtime selection in `osrv` is always explicit.

There are two ways to select a runtime:
- pass a `RuntimeConfig` into `serve(...)`
- choose a `FetchEntryRuntime` in `defineFetchEntry(...)`

## Serve-Based Runtimes

These runtimes use `serve(server, runtimeConfig)`:
- `dart`
- `node`
- `bun`

### `DartRuntimeConfig`

Import:

```dart
import 'package:osrv/runtime/dart.dart';
```

Fields:

| Field | Default | Meaning |
| --- | --- | --- |
| `host` | `'127.0.0.1'` | Host interface passed to `HttpServer.bind` |
| `port` | `3000` | Port passed to `HttpServer.bind` |
| `backlog` | `0` | Backlog passed to `HttpServer.bind` |
| `shared` | `false` | Whether the socket can be shared |
| `v6Only` | `false` | Whether IPv6 sockets reject IPv4-mapped connections |

Validation:
- `host` must not be empty
- `port` must be between `0` and `65535`
- `backlog` must not be negative

### `NodeRuntimeConfig`

Import:

```dart
import 'package:osrv/runtime/node.dart';
```

Fields:

| Field | Default | Meaning |
| --- | --- | --- |
| `host` | `'127.0.0.1'` | Host interface passed to the Node HTTP server |
| `port` | `3000` | Listener port |

Validation:
- `host` must not be empty
- `port` must be between `0` and `65535`

### `BunRuntimeConfig`

Import:

```dart
import 'package:osrv/runtime/bun.dart';
```

Fields:

| Field | Default | Meaning |
| --- | --- | --- |
| `host` | `'127.0.0.1'` | Host interface passed to `Bun.serve` |
| `port` | `3000` | Listener port |

Validation:
- `host` must not be empty
- `port` must be between `0` and `65535`

## Entry-Export Runtimes

These runtimes do not use `RuntimeConfig` today:
- `cloudflare`
- `vercel`

Use:

```dart
defineFetchEntry(
  server,
  runtime: FetchEntryRuntime.cloudflare,
);
```

Optional entry name override:

```dart
defineFetchEntry(
  server,
  runtime: FetchEntryRuntime.vercel,
  name: '__custom_fetch__',
);
```

Validation:
- `name` must not be empty or whitespace-only

Default:
- `defaultFetchEntryName == '__osrv_fetch__'`

## Selection Examples

Serve-based:

```dart
final runtime = await serve(
  server,
  const NodeRuntimeConfig(host: '0.0.0.0', port: 3000),
);
```

Entry-export:

```dart
void main() {
  defineFetchEntry(
    server,
    runtime: FetchEntryRuntime.cloudflare,
  );
}
```

## Import Rule

Use runtime-family entrypoints:
- `package:osrv/runtime/dart.dart`
- `package:osrv/runtime/node.dart`
- `package:osrv/runtime/bun.dart`

Do not import `package:osrv/src/runtime/...` config files directly.
