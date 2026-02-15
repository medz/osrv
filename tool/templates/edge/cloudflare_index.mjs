import { isBridgeHandler, runBridgeHandler, waitForMain } from '../../shared/bridge.mjs';

if (typeof globalThis.self === 'undefined') {
  globalThis.self = globalThis;
}
await import('../../js/core/{{CORE_JS_NAME}}');

const CONTEXT_DEFAULTS = {
  provider: 'cloudflare',
  runtime: 'cloudflare',
  protocol: 'http',
  httpVersion: '1.1',
};

function normalizeEnv(env) {
  if (env && typeof env === 'object') {
    return env;
  }
  return {};
}

function buildContext(request, env, ctx) {
  let protocol = 'http';
  try {
    protocol = new URL(request.url).protocol.replace(':', '') || 'http';
  } catch (_) {}
  const ip = request.headers.get('cf-connecting-ip');
  return {
    provider: 'cloudflare',
    runtime: 'cloudflare',
    protocol,
    httpVersion: '1.1',
    tls: protocol === 'https',
    ip: ip || null,
    env: normalizeEnv(env),
    waitUntil: (promise) => ctx?.waitUntil?.(promise),
    ctx,
    raw: { env, ctx },
  };
}

async function handle(request, context) {
  const main = await waitForMain();
  if (typeof main !== 'function') {
    return new Response('globalThis.__osrv_main__ is not set.', { status: 500 });
  }
  if (isBridgeHandler(main)) {
    return runBridgeHandler(main, request, context, CONTEXT_DEFAULTS);
  }
  return main(request, context);
}

export default {
  async fetch(request, env, ctx) {
    return handle(request, buildContext(request, env, ctx));
  },
};
