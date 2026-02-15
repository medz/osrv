# End-to-End Examples

## A. Dart native run

In your app package:

```bash
dart pub get
dart run osrv serve
```

## B. Build once, direct deploy in Node/Bun/Deno

```bash
dart run osrv build

node dist/js/node/index.mjs
bun run dist/js/bun/index.mjs
deno run -A dist/js/deno/index.mjs
```

These adapters load `dist/js/core/<entry>.js` directly.

## C. Edge adapter invocation

Cloudflare-style example:

```js
import edge from './dist/edge/cloudflare/index.mjs';

const response = await edge.fetch(
  new Request('https://example.com/'),
  { TOKEN: 'demo' },
  { waitUntil() {} },
);
```

`index.mjs` directly uses the Dart-built core handler registered by your entry.
