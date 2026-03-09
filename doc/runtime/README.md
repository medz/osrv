# Runtime Docs

Use this directory to choose a runtime family and see its real setup, capabilities, extension access, and current limits.

## Runtime Summary

| Runtime | Import | Entry model | Returns `Runtime` | Main extension |
| --- | --- | --- | --- | --- |
| `dart` | `package:osrv/runtime/dart.dart` | `serve(...)` | yes | `DartRuntimeExtension` |
| `node` | `package:osrv/runtime/node.dart` | `serve(...)` | yes | `NodeRuntimeExtension` |
| `bun` | `package:osrv/runtime/bun.dart` | `serve(...)` | yes | `BunRuntimeExtension` |
| `cloudflare` | `package:osrv/runtime/cloudflare.dart` | `defineFetchExport(...)` | no | `CloudflareRuntimeExtension<Env, Request>` |
| `vercel` | `package:osrv/runtime/vercel.dart` | `defineFetchExport(...)` | no | `VercelRuntimeExtension<Request>` |

## Runtime Pages

- [dart](./dart.md)
- [node](./node.md)
- [bun](./bun.md)
- [cloudflare](./cloudflare.md)
- [vercel](./vercel.md)

## Related Docs

- [config](../config.md)
- [capabilities](../capabilities.md)
- [usage examples](../examples/final-usage.md)
