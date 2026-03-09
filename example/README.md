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
mkdir -p example/api
dart compile js example/vercel.dart -o example/api/index.dart.js
```

The JavaScript shims are:

- [`cloudflare.mjs`](./cloudflare.mjs)
- [`api/index.mjs`](./api/index.mjs)

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

## Vercel Function Example

This directory also includes:

- [`package.json`](./package.json)
- [`vercel.json`](./vercel.json)
- [`api/index.mjs`](./api/index.mjs)

Use them from inside `example/`:

```bash
npm install
npm run build:vercel
vercel dev
```

`api/index.mjs` sets `globalThis.self` before loading the compiled Dart module.
That bootstrap must happen in JavaScript; doing it from Dart interop is too late.
