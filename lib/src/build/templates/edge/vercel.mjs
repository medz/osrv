import { isBridgeHandler, runBridgeHandler, waitForMain } from '../../shared/bridge.mjs';

if (typeof globalThis.self === 'undefined') {
  globalThis.self = globalThis;
}
await import('../../js/core/{{CORE_JS_NAME}}');

const CONTEXT_DEFAULTS = {
  provider: 'vercel',
  runtime: 'vercel',
  protocol: 'http',
  httpVersion: '1.1',
};

function normalizeEnv(context) {
  if (context?.env && typeof context.env === 'object') {
    return context.env;
  }
  return {};
}

function buildContext(request, context) {
  let protocol = 'http';
  try {
    protocol = new URL(request.url).protocol.replace(':', '') || 'http';
  } catch (_) {}

  return {
    provider: 'vercel',
    runtime: 'vercel',
    protocol,
    httpVersion: '1.1',
    tls: protocol === 'https',
    env: normalizeEnv(context),
    waitUntil: (promise) => context?.waitUntil?.(promise),
    ctx: context,
    raw: { context },
  };
}

export default async function handler(request, context) {
  const main = await waitForMain();
  if (typeof main !== 'function') {
    return new Response('globalThis.__osrv_main__ is not set.', { status: 500 });
  }

  const normalized = buildContext(request, context);
  if (isBridgeHandler(main)) {
    return runBridgeHandler(main, request, normalized, CONTEXT_DEFAULTS);
  }
  return main(request, normalized);
}
