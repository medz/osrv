# osrv Docs

`osrv` is a unified server runtime for Dart applications.

It gives you one `Server` contract and two explicit host entry models:
- runtime-specific `serve(server, {platform params})` for listener-style runtimes
- runtime-specific `defineFetchExport(server)` for fetch-export runtimes

Current runtime families:
- `dart`
- `node`
- `bun`
- `deno`
- `cloudflare`
- `vercel`
- `netlify`

Current global limitation:
- websocket support is not implemented yet, so `runtime.capabilities.websocket` is `false` everywhere

## Start Here

- [architecture](./architecture.md): what `osrv` provides and how to choose an entry model
- [config](./config.md): runtime selection, config fields, and validation rules
- [capabilities](./capabilities.md): capability meanings and the current support matrix
- [websocket support spec](./specs/websocket-support.md): draft websocket API direction and rollout plan
- [runtime docs](./runtime/README.md): runtime-by-runtime setup, limits, and extension access

## API Reference

- [core API](./api/core.md): `Server`, `RequestContext`, `Runtime`, and errors
- [runtime API](./api/runtime.md): runtime selection model and runtime-family entrypoints
- [public surface](./api/public-surface.md): the stable package entrypoints you should import

## Examples

- [usage examples](./examples/final-usage.md)

## Import Rule

Application code should import only:
- `package:osrv/osrv.dart`
- `package:osrv/runtime/*.dart`

Do not build against `package:osrv/src/...` paths.
