import { isBridgeHandler, runBridgeHandler, waitForMain } from '../../shared/bridge.mjs';

if (typeof globalThis.self === 'undefined') {
  globalThis.self = globalThis;
}
await import('../core/{{CORE_JS_NAME}}');

const CONTEXT_DEFAULTS = {
  provider: 'deno',
  runtime: 'deno',
  protocol: 'http',
  httpVersion: '1.1',
};

function formatAddr(addr) {
  if (!addr || typeof addr !== 'object') return null;
  if (typeof addr.hostname === 'string' && typeof addr.port === 'number') {
    return String(addr.hostname) + ':' + String(addr.port);
  }
  return null;
}

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
  const port = Number(options.port ?? Deno.env.get('PORT') ?? 3000);
  const hostname = String(options.hostname ?? Deno.env.get('HOSTNAME') ?? '0.0.0.0');

  return Deno.serve({ port, hostname }, (request, info) => {
    let protocol = 'http';
    try {
      protocol = new URL(request.url).protocol.replace(':', '') || 'http';
    } catch (_) {}
    return dispatch(request, {
      provider: 'deno',
      runtime: 'deno',
      protocol,
      httpVersion: '1.1',
      localAddress: formatAddr(info?.localAddr),
      remoteAddress: formatAddr(info?.remoteAddr),
      ip: info?.remoteAddr?.hostname ?? null,
      tls: protocol === 'https',
      env: {},
      raw: { info },
    });
  });
}

if (import.meta.main) {
  await serve();
}
