import { isBridgeHandler, runBridgeHandler, waitForMain } from '../../shared/bridge.mjs';

if (typeof globalThis.self === 'undefined') {
  globalThis.self = globalThis;
}
await import('../core/{{CORE_JS_NAME}}');

const CONTEXT_DEFAULTS = {
  provider: 'bun',
  runtime: 'bun',
  protocol: 'http',
  httpVersion: '1.1',
};

function createDispatcher(mainHandler) {
  if (isBridgeHandler(mainHandler)) {
    return (request, context) =>
      runBridgeHandler(mainHandler, request, context, CONTEXT_DEFAULTS);
  }

  return (request, context) => mainHandler(request, context);
}

export async function serve(options = {}) {
  const main = await waitForMain();
  if (typeof main !== 'function') {
    throw new Error(
      'globalThis.__osrv_main__ is not set. Build output expects Dart JS core to register handler. Check dist/js/core/{{CORE_JS_NAME}}.',
    );
  }

  const dispatch = createDispatcher(main);
  const port = Number(options.port ?? process.env.PORT ?? 3000);
  const hostname = String(options.hostname ?? process.env.HOSTNAME ?? '0.0.0.0');

  return Bun.serve({
    port,
    hostname,
    development: false,
    reusePort: Boolean(options.reusePort ?? false),
    fetch(request, server) {
      let protocol = 'http';
      try {
        protocol = new URL(request.url).protocol.replace(':', '') || 'http';
      } catch (_) {}
      return dispatch(request, {
        provider: 'bun',
        runtime: 'bun',
        protocol,
        httpVersion: '1.1',
        tls: protocol === 'https',
        env: {},
        raw: { server },
      });
    },
  });
}

if (import.meta.main) {
  await serve();
}
