# osrv_example

Minimal non-publishable pub package that depends on `osrv` via a local path.

## Run

```bash
dart pub get
dart run osrv serve
```

This uses `server.dart` by default.

## Build

```bash
dart pub get
dart run osrv build
```

Build output:

- `dist/bin/server` (or `dist/bin/server.exe` on Windows)
- `dist/js/core/server.js`
- Node/Bun/Deno direct deploy adapters under `dist/js/*`
- edge direct deploy adapters under `dist/edge/*`

If you want to run source directly without osrv CLI:

```bash
dart run server.dart
```
