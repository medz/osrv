# osrv benchmark

Run the benchmark from this directory:

```bash
dart pub get
dart run bin/bench.dart --requests=200 --max-overhead=0.05
```

Scenarios:

- `baseline`: plain `dart:io` `HttpServer`
- `osrv`: `package:osrv`
- `shelf`: `package:shelf`
- `relic`: `package:relic`

Useful options:

- `--requests`: measured requests per round (default `200`)
- `--warmup`: warmup requests per round (default `50`)
- `--rounds`: number of rounds (default `7`)
- `--burn-in-rounds`: warm-up rounds before reporting (default `2`)
- `--concurrency`: concurrent in-flight requests (default `8`)
- `--max-overhead`: allowed median round overhead fraction of `osrv` vs baseline (default `0.05`)
