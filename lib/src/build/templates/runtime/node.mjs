import { readFileSync } from 'node:fs';
import { createServer as createHttpServer } from 'node:http';
import { createSecureServer as createHttp2SecureServer } from 'node:http2';
import { fileURLToPath } from 'node:url';
import { isBridgeHandler, runBridgeHandler, waitForMain } from '../../shared/bridge.mjs';

if (typeof globalThis.self === 'undefined') {
  globalThis.self = globalThis;
}

function setRuntimeCapabilities(next) {
  const current =
    globalThis.__osrv_runtime_capabilities__ &&
    typeof globalThis.__osrv_runtime_capabilities__ === 'object'
      ? globalThis.__osrv_runtime_capabilities__
      : {};
  globalThis.__osrv_runtime_capabilities__ = {
    ...current,
    ...next,
  };
}

function hasTlsFromEnvironment() {
  const cert = process.env.OSRV_TLS_CERT ?? process.env.TLS_CERT;
  const key = process.env.OSRV_TLS_KEY ?? process.env.TLS_KEY;
  return typeof cert === 'string' && cert.length > 0 && typeof key === 'string' && key.length > 0;
}

const presetProtocol = String(process.env.OSRV_PROTOCOL ?? 'http').toLowerCase();
setRuntimeCapabilities({
  http2: presetProtocol === 'https' && hasTlsFromEnvironment(),
});

await import('../core/{{CORE_JS_NAME}}');

const CONTEXT_DEFAULTS = {
  provider: 'node',
  runtime: 'node',
  protocol: 'http',
  httpVersion: '1.1',
};
const BODY_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);
const HOP_BY_HOP_HEADERS = new Set([
  'connection',
  'keep-alive',
  'proxy-connection',
  'transfer-encoding',
  'upgrade',
]);

function readPemOrFile(value) {
  if (typeof value !== 'string' || value.length === 0) {
    return null;
  }
  if (value.includes('-----BEGIN ')) {
    return value;
  }
  return readFileSync(value);
}

function resolveTlsOptions(options) {
  const tlsInput =
    options.tls && typeof options.tls === 'object' ? options.tls : {};
  const certInput =
    tlsInput.cert ?? options.cert ?? process.env.OSRV_TLS_CERT ?? process.env.TLS_CERT;
  const keyInput =
    tlsInput.key ?? options.key ?? process.env.OSRV_TLS_KEY ?? process.env.TLS_KEY;
  const passphrase =
    tlsInput.passphrase ??
    options.passphrase ??
    process.env.OSRV_TLS_PASSPHRASE ??
    process.env.TLS_PASSPHRASE ??
    null;

  const cert = readPemOrFile(certInput);
  const key = readPemOrFile(keyInput);

  if ((cert && !key) || (!cert && key)) {
    throw new Error(
      'TLS requires both cert and key. Set both `tls.cert` and `tls.key` (or OSRV_TLS_CERT/OSRV_TLS_KEY).',
    );
  }
  if (!cert || !key) {
    return null;
  }

  return {
    cert,
    key,
    passphrase: typeof passphrase === 'string' && passphrase.length > 0 ? passphrase : undefined,
  };
}

function normalizeHttpVersion(value) {
  if (typeof value !== 'string' || value.length === 0) {
    return '1.1';
  }
  return value.startsWith('2') ? '2' : value;
}

function toRequestHeaders(input) {
  const headers = new Headers();
  const source = input && typeof input === 'object' ? input : {};
  for (const [name, raw] of Object.entries(source)) {
    if (name.startsWith(':') || raw == null) {
      continue;
    }
    if (Array.isArray(raw)) {
      for (const value of raw) {
        headers.append(name, String(value));
      }
      continue;
    }
    headers.append(name, String(raw));
  }
  return headers;
}

function toFetchRequest(nodeReq, { hostname, port, protocol }) {
  const origin = protocol + '://' + hostname + ':' + port;
  const url = new URL(nodeReq.url || '/', origin);
  const method = (nodeReq.method || 'GET').toUpperCase();
  const init = { method, headers: toRequestHeaders(nodeReq.headers) };
  if (BODY_METHODS.has(method)) {
    init.body = nodeReq;
    init.duplex = 'half';
  }
  return new Request(url, init);
}

async function writeNodeResponse(nodeRes, response) {
  nodeRes.statusCode = response.status;
  for (const [key, value] of response.headers) {
    if (normalizeHttpVersion(nodeRes.req?.httpVersion || '1.1') === '2' && HOP_BY_HOP_HEADERS.has(key.toLowerCase())) {
      continue;
    }
    nodeRes.setHeader(key, value);
  }
  if (response.body) {
    const bytes = Buffer.from(await response.arrayBuffer());
    nodeRes.end(bytes);
    return;
  }
  nodeRes.end();
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
  const port = Number(options.port ?? process.env.PORT ?? 3000);
  const hostname = String(options.hostname ?? process.env.HOSTNAME ?? '0.0.0.0');
  const tls = resolveTlsOptions(options);
  const requestedProtocol = String(
    options.protocol ?? process.env.OSRV_PROTOCOL ?? (tls ? 'https' : 'http'),
  ).toLowerCase();
  const protocol = requestedProtocol === 'https' && tls ? 'https' : 'http';
  if (requestedProtocol === 'https' && !tls) {
    console.warn(
      '[osrv/node] HTTPS requested without TLS cert/key, falling back to HTTP/1.1.',
    );
  }

  const requestHandler = async (req, res) => {
    try {
      const isTls = Boolean(req.socket?.encrypted);
      const requestProtocol = isTls ? 'https' : 'http';
      const request = toFetchRequest(req, {
        hostname,
        port,
        protocol: requestProtocol,
      });
      const localAddress =
        req.socket?.localAddress && req.socket?.localPort
          ? String(req.socket.localAddress) + ':' + String(req.socket.localPort)
          : null;
      const remoteAddress =
        req.socket?.remoteAddress && req.socket?.remotePort
          ? String(req.socket.remoteAddress) +
            ':' +
            String(req.socket.remotePort)
          : null;
      const response = await dispatch(request, {
        provider: 'node',
        runtime: 'node',
        protocol: requestProtocol,
        httpVersion: normalizeHttpVersion(req.httpVersion || '1.1'),
        localAddress,
        remoteAddress,
        ip: req.socket?.remoteAddress ?? null,
        tls: isTls,
        env: {},
        raw: { req, res },
      });
      await writeNodeResponse(res, response);
    } catch (error) {
      res.statusCode = 500;
      res.end('Internal Server Error');
      console.error('[osrv/node] request handling failed', error);
    }
  };

  const server =
    protocol === 'https'
      ? createHttp2SecureServer(
          {
            cert: tls.cert,
            key: tls.key,
            passphrase: tls.passphrase,
            allowHTTP1: true,
          },
          requestHandler,
        )
      : createHttpServer(requestHandler);

  setRuntimeCapabilities({
    http2: protocol === 'https',
  });

  server.listen(port, hostname);
  return server;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  await serve();
}
