# osrv

Dart-first unified server core with a single `Server(...)` API.

## Status

- Core API implemented: `Server`, middleware, plugins, lifecycle, error handling.
- `dart:io` runtime transport implemented and tested.
- WebSocket upgrade helper implemented for `dart:io`.
- Build pipeline implemented with `dart run tool/build.dart`.
- JS/Edge adapters are generated as scaffolds under `dist/` and are ready for runtime-bridge wiring.

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

CLI config precedence:

1. CLI flags
2. Environment variables
3. `osrv.config.dart` (best-effort parse)
4. Defaults

## Build

```bash
dart run tool/build.dart
```

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

Benchmark gate (fractional overhead, `0.05` == 5%):

```bash
dart run tool/bench.dart --requests=200 --max-overhead=0.05
```
