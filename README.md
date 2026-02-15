# osrv

Dart-first unified server core with a single `Server(...)` API.

## Status

- Core API implemented: `Server`, middleware, plugins, lifecycle, error handling.
- `dart:io` runtime transport implemented and tested.
- WebSocket upgrade helper implemented for `dart:io`.
- Maintainer helper script available at `dart run tool/build.dart` (delegates to CLI build).
- `dart run osrv build` generates direct-deploy Node/Bun/Deno/Edge adapters under `dist/` that load Dart-compiled JS core.

## Install

```bash
dart pub get
```

## Use osrv in your own package

`osrv` is meant to be used as a dependency from another Dart package:

```yaml
name: my_server_app
publish_to: none

environment:
  sdk: ^3.10.0

dependencies:
  osrv:
    path: ../osrv
```

Then create `bin/main.dart`:

```dart
import 'package:osrv/osrv.dart';

Future<void> main() async {
  final server = Server(
    fetch: (request) => Response.json({'ok': true, 'path': request.url.path}),
  );
  await server.serve();
}
```

## Example package

`/example` is a minimal non-publishable pub package that depends on `osrv` via path dependency.

```bash
cd example
dart pub get
dart run osrv serve
dart run osrv build
```

## Quick start

```dart
import 'package:osrv/osrv.dart';

Future<void> main() async {
  final server = Server(
    fetch: (request) async {
      return Response.json({'ok': true, 'path': request.url.path});
    },
  );

  await server.serve();
}
```

## CLI

```bash
dart run osrv serve
dart run osrv build
```

`serve` defaults to `server.dart` (fallback: `bin/server.dart`), and `build` also defaults to the same entry.

Dependency-mode workflow (inside your app package):

1. Add `osrv` dependency.
2. Create `server.dart` with your server entrypoint.
3. Run `dart run osrv serve` for local run.
4. Run `dart run osrv build` for distributable artifacts.

CLI config precedence:

1. CLI flags
2. Environment variables
3. Defaults

Programmatic build API (for downstream packages):

```dart
import 'package:osrv/build.dart';

Future<void> main() async {
  await build(
    const BuildOptions(
      entry: 'server.dart',
      outDir: 'dist',
    ),
  );
}
```

## Maintainer Build Helper

```bash
dart run tool/build.dart
```

This is for local osrv repo development convenience.
User/application build flow remains `dart run osrv build`.

Artifacts:

- `dist/js/<runtime>/`
- `dist/edge/<provider>/`
- `dist/bin/`

## Test

```bash
dart test
```

Contract runner:

```bash
dart run tool/contract.dart
```

Multi-runtime contract matrix (auto-detects available runtimes):

```bash
dart run tool/contract_matrix.dart
```

Benchmark gate (fractional overhead, `0.05` == 5%):

```bash
dart run tool/bench.dart --requests=200 --max-overhead=0.05
```

## Docs

- [`docs/troubleshooting.md`](docs/troubleshooting.md)
- [`docs/examples.md`](docs/examples.md)
