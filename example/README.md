# osrv_example

Minimal non-publishable pub package that depends on `osrv` via a local path.

## Run

```bash
dart pub get
dart run osrv serve
```

## Build

```bash
dart pub get
dart run osrv build
```

Build output:

- `dist/bin/server` (or `dist/bin/server.exe` on Windows)
- `dist/js/core/server.js`
- runtime adapter scaffolds under `dist/js/*` and `dist/edge/*`

If you want to run source directly without osrv CLI:

```bash
dart run server.dart
```
