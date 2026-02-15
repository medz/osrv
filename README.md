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
dart run bin/osrv.dart serve --entry example/main.dart
```

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
