import { readFileSync } from 'node:fs';
import { createServer as createHttpServer } from 'node:http';
import { createSecureServer as createHttp2SecureServer } from 'node:http2';
import { fileURLToPath } from 'node:url';
import { isBridgeHandler, runBridgeHandler, waitForMain } from '../../shared/bridge.mjs';

if (typeof globalThis.self === 'undefined') {
  globalThis.self = globalThis;
}

const DEFAULT_RUNTIME_CONTEXT = {
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

function toRuntimeEnv(envLike) {
  const env = {};
  if (!envLike || typeof envLike !== 'object') {
    return env;
  }
  for (const [key, value] of Object.entries(envLike)) {
    if (value == null) {
      continue;
    }
    env[String(key)] = String(value);
  }
  return env;
}

const presetProtocol = String(process.env.OSRV_PROTOCOL ?? 'http').toLowerCase();
setRuntimeCapabilities({
  http2: presetProtocol === 'https' && hasTlsFromEnvironment(),
});

await import('../core/{{CORE_JS_NAME}}');

function readPemOrFile(value) {
  if (value == null) {
    return null;
  }
  if (typeof value !== 'string') {
    return value;
  }
  if (value.includes('-----BEGIN ')) {
    return value;
  }
  return readFileSync(value);
}

export function resolveTlsOptions(options = {}, env = process.env) {
  const tlsInput =
    options.tls && typeof options.tls === 'object' ? options.tls : {};
  const certInput =
    tlsInput.cert ?? options.cert ?? env.OSRV_TLS_CERT ?? env.TLS_CERT;
  const keyInput =
    tlsInput.key ?? options.key ?? env.OSRV_TLS_KEY ?? env.TLS_KEY;
  const passphrase =
    tlsInput.passphrase ??
    options.passphrase ??
    env.OSRV_TLS_PASSPHRASE ??
    env.TLS_PASSPHRASE ??
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

function normalizeRuntimeConfig(overrides = {}) {
  const provider = String(overrides.provider ?? DEFAULT_RUNTIME_CONTEXT.provider);
  const runtime = String(overrides.runtime ?? provider);
  return {
    provider,
    runtime,
    logPrefix: String(overrides.logPrefix ?? `[osrv/${runtime}]`),
    allowHTTP1: Boolean(overrides.allowHTTP1 ?? true),
    contextDefaults: {
      ...DEFAULT_RUNTIME_CONTEXT,
      provider,
      runtime,
    },
  };
}

function createDispatcher(mainHandler, contextDefaults) {
  if (isBridgeHandler(mainHandler)) {
    return (request, context) =>
      runBridgeHandler(mainHandler, request, context, contextDefaults);
  }

  return (request, context) => mainHandler(request, context);
}

function createNodeRequestHandler({
  dispatch,
  hostname,
  port,
  runtimeConfig,
  runtimeEnv,
}) {
  return async (req, res) => {
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
        provider: runtimeConfig.provider,
        runtime: runtimeConfig.runtime,
        protocol: requestProtocol,
        httpVersion: normalizeHttpVersion(req.httpVersion || '1.1'),
        localAddress,
        remoteAddress,
        ip: req.socket?.remoteAddress ?? null,
        tls: isTls,
        env: runtimeEnv,
        raw: { req, res },
      });
      await writeNodeResponse(res, response);
    } catch (error) {
      res.statusCode = 500;
      res.end('Internal Server Error');
      console.error(`${runtimeConfig.logPrefix} request handling failed`, error);
    }
  };
}

async function resolveMainHandler(options = {}) {
  if (typeof options.mainHandler === 'function') {
    return options.mainHandler;
  }

  const main = await waitForMain();
  if (typeof main !== 'function') {
    throw new Error(
      'globalThis.__osrv_main__ is not set. Build output expects Dart JS core to register handler. Check dist/js/core/{{CORE_JS_NAME}}.',
    );
  }

  return main;
}

export async function serveWithNodeHttp2(
  options = {},
  runtimeOverrides = {},
) {
  const runtimeConfig = normalizeRuntimeConfig(runtimeOverrides);
  const main = await resolveMainHandler(options);
  const dispatch = createDispatcher(main, runtimeConfig.contextDefaults);
  const port = Number(options.port ?? process.env.PORT ?? 3000);
  const hostname = String(options.hostname ?? process.env.HOSTNAME ?? '0.0.0.0');
  const runtimeEnv = toRuntimeEnv(process.env);
  const tls = resolveTlsOptions(options);
  if (!tls) {
    throw new Error(
      `${runtimeConfig.logPrefix} HTTPS HTTP/2 requires TLS cert/key.`,
    );
  }

  const requestHandler = createNodeRequestHandler({
    dispatch,
    hostname,
    port,
    runtimeConfig,
    runtimeEnv,
  });

  const server = createHttp2SecureServer(
    {
      cert: tls.cert,
      key: tls.key,
      passphrase: tls.passphrase,
      allowHTTP1: runtimeConfig.allowHTTP1,
    },
    requestHandler,
  );
  server.listen(port, hostname);
  return server;
}

export async function serve(options = {}) {
  const runtimeConfig = normalizeRuntimeConfig();
  const main = await resolveMainHandler(options);
  const dispatch = createDispatcher(main, runtimeConfig.contextDefaults);
  const port = Number(options.port ?? process.env.PORT ?? 3000);
  const hostname = String(options.hostname ?? process.env.HOSTNAME ?? '0.0.0.0');
  const runtimeEnv = toRuntimeEnv(process.env);
  const tls = resolveTlsOptions(options);
  const requestedProtocol = String(
    options.protocol ?? process.env.OSRV_PROTOCOL ?? (tls ? 'https' : 'http'),
  ).toLowerCase();
  const protocol = requestedProtocol === 'https' && tls ? 'https' : 'http';
  if (requestedProtocol === 'https' && !tls) {
    console.warn(
      `${runtimeConfig.logPrefix} HTTPS requested without TLS cert/key, falling back to HTTP/1.1.`,
    );
  }

  if (protocol === 'https') {
    const server = await serveWithNodeHttp2(
      {
        ...options,
        port,
        hostname,
        protocol: 'https',
        tls,
        mainHandler: main,
      },
      runtimeConfig,
    );
    setRuntimeCapabilities({ http2: true });
    return server;
  }

  const requestHandler = createNodeRequestHandler({
    dispatch,
    hostname,
    port,
    runtimeConfig,
    runtimeEnv,
  });
  const server = createHttpServer(requestHandler);
  server.listen(port, hostname);
  setRuntimeCapabilities({ http2: false });
  return server;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  await serve();
}
