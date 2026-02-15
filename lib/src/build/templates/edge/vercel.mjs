import {
  isBridgeHandler,
  isUpgradeBridgeResponse,
  runBridgeHandler,
  waitForMain,
} from '../../shared/bridge.mjs';
import { setRuntimeCapabilities } from '../../shared/runtime_utils.mjs';

if (typeof globalThis.self === 'undefined') {
  globalThis.self = globalThis;
}

// Vercel Edge runtime does not provide inbound websocket upgrade support.
setRuntimeCapabilities({ websocket: false });

await import('../../js/core/{{CORE_JS_NAME}}');

const CONTEXT_DEFAULTS = {
  provider: 'vercel',
  runtime: 'vercel',
  protocol: 'http',
  httpVersion: '1.1',
};

let wsRequestSequence = 0;
function nextRequestId() {
  wsRequestSequence += 1;
  return `vercel-ws-req-${wsRequestSequence}`;
}

function normalizeEnv(context) {
  if (context?.env && typeof context.env === 'object') {
    return context.env;
  }
  return {};
}

function buildContext(request, context, requestId) {
  let protocol = 'http';
  try {
    protocol = new URL(request.url).protocol.replace(':', '') || 'http';
  } catch (_) {}

  return {
    provider: 'vercel',
    runtime: 'vercel',
    protocol,
    httpVersion: '1.1',
    requestId,
    tls: protocol === 'https',
    env: normalizeEnv(context),
    waitUntil: (promise) => context?.waitUntil?.(promise),
    ctx: context,
    raw: { context, requestId },
  };
}

export default async function handler(request, context) {
  const main = await waitForMain();
  if (typeof main !== 'function') {
    return new Response('globalThis.__osrv_main__ is not set.', { status: 500 });
  }

  const requestId = nextRequestId();
  const normalized = buildContext(request, context, requestId);
  const response = isBridgeHandler(main)
    ? await runBridgeHandler(main, request, normalized, CONTEXT_DEFAULTS)
    : await main(request, normalized);

  if (isUpgradeBridgeResponse(response)) {
    return new Response(
      'WebSocket upgrade is not supported in Vercel Edge runtime.',
      { status: 501 },
    );
  }

  return response;
}
