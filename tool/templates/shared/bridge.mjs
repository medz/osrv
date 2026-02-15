const BODY_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);
const BRIDGE_MODE = 'json-v1';

export function getMainHandler() {
  return globalThis.__osrv_main__;
}

export async function waitForMain(timeoutMs = 5000) {
  const startedAt = Date.now();
  while (Date.now() - startedAt <= timeoutMs) {
    const handler = getMainHandler();
    if (typeof handler === 'function') {
      return handler;
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  return null;
}

export function isBridgeHandler(handler) {
  return (
    typeof handler === 'function' &&
    handler.__osrv_bridge__ === BRIDGE_MODE
  );
}

function bytesToBase64(bytes) {
  if (typeof Buffer !== 'undefined') {
    return Buffer.from(bytes).toString('base64');
  }
  let binary = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

function base64ToBytes(base64) {
  if (typeof Buffer !== 'undefined') {
    return new Uint8Array(Buffer.from(base64, 'base64'));
  }
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

export function normalizeRuntimeContext(input = {}, defaults = {}) {
  const value = input && typeof input === 'object' ? input : {};
  const env =
    value.env && typeof value.env === 'object' && value.env !== null
      ? value.env
      : defaults.env && typeof defaults.env === 'object'
        ? defaults.env
        : {};
  const protocol =
    typeof value.protocol === 'string'
      ? value.protocol
      : typeof defaults.protocol === 'string'
        ? defaults.protocol
        : 'http';

  return {
    provider:
      typeof value.provider === 'string'
        ? value.provider
        : defaults.provider ?? 'unknown',
    runtime:
      typeof value.runtime === 'string'
        ? value.runtime
        : defaults.runtime ?? 'unknown',
    protocol,
    httpVersion:
      typeof value.httpVersion === 'string'
        ? value.httpVersion
        : defaults.httpVersion ?? '1.1',
    localAddress:
      typeof value.localAddress === 'string' ? value.localAddress : null,
    remoteAddress:
      typeof value.remoteAddress === 'string' ? value.remoteAddress : null,
    ip: typeof value.ip === 'string' ? value.ip : null,
    tls: Boolean(value.tls ?? defaults.tls ?? protocol === 'https'),
    env,
  };
}

export async function serializeRequest(request, bodyMethods = BODY_METHODS) {
  const headers = [];
  for (const [name, value] of request.headers.entries()) {
    headers.push([name, value]);
  }

  const method = (request.method || 'GET').toUpperCase();
  let bodyBase64 = null;
  if (bodyMethods.has(method)) {
    const clone = request.clone();
    const buffer = await clone.arrayBuffer();
    if (buffer.byteLength > 0) {
      bodyBase64 = bytesToBase64(new Uint8Array(buffer));
    }
  }

  return {
    url: request.url,
    method,
    headers,
    bodyBase64,
  };
}

export function responseFromBridgePayload(responsePayload) {
  const payload =
    typeof responsePayload === 'string'
      ? JSON.parse(responsePayload)
      : responsePayload;
  if (!payload || typeof payload !== 'object') {
    throw new Error('Invalid bridge response payload.');
  }

  const status = Number(payload.status ?? 500);
  const headers = new Headers();
  if (Array.isArray(payload.headers)) {
    for (const entry of payload.headers) {
      if (Array.isArray(entry) && entry.length >= 2) {
        headers.append(String(entry[0]), String(entry[1]));
      }
    }
  }

  let body = null;
  if (typeof payload.bodyBase64 === 'string' && payload.bodyBase64.length > 0) {
    body = base64ToBytes(payload.bodyBase64);
  }

  return new Response(body, { status, headers });
}

export async function runBridgeHandler(
  handler,
  request,
  context = {},
  defaults = {},
  contextBag = {},
) {
  const payload = JSON.stringify({
    request: await serializeRequest(request),
    runtime: normalizeRuntimeContext(context, defaults),
    context: contextBag,
  });
  const result = await new Promise((resolve, reject) => {
    try {
      handler(payload, resolve, reject);
    } catch (error) {
      reject(error);
    }
  });
  return responseFromBridgePayload(result);
}
