# Example

This directory contains minimal runnable examples for the officially supported
`osrv` runtime families.

Included entries:
- `dart.dart`
- `node.dart`
- `bun.dart`
- `cloudflare.dart`
- `vercel.dart`

All entries share the same [`server.dart`](./server.dart) definition.
That server only returns:

```text
Hello Osrv!
```

## Dart Runtime

Run the Dart-hosted example directly from the package root:

```bash
dart run example/dart.dart
```

## Node and Bun Runtimes

The `node` and `bun` examples must run on their target JavaScript hosts.

Compile them first:

```bash
dart compile js example/node.dart -o example/node.dart.js
dart compile js example/bun.dart -o example/bun.dart.js
```

Then run them with their matching hosts:

```bash
node example/node.dart.js
bun example/bun.dart.js
```

## Fetch-Export Hosts

Compile the entry to JavaScript, then use the matching shim:

```bash
dart compile js example/cloudflare.dart -o example/cloudflare.dart.js
dart compile js example/vercel.dart -o example/vercel.dart.js
```

The JavaScript shims are:
- [`cloudflare.js`](./cloudflare.js)
- [`vercel.js`](./vercel.js)

## Cloudflare Worker Example

This directory also includes:
- [`package.json`](./package.json)
- [`wrangler.json`](./wrangler.json)

Use them from inside `example/`:

```bash
npm install
npm run build:cloudflare
npm run dev:cloudflare
```
