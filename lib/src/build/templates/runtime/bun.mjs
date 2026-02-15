import { serveWithNodeHttp2 } from '../node/index.mjs';
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

function parseBoolean(value) {
  if (typeof value === 'boolean') {
    return value;
  }
  if (typeof value === 'number') {
    return value !== 0;
  }
  if (typeof value !== 'string') {
    return null;
  }
  const normalized = value.trim().toLowerCase();
  if (
    normalized === '1' ||
    normalized === 'true' ||
    normalized === 'yes' ||
    normalized === 'on'
  ) {
    return true;
  }
  if (
    normalized === '0' ||
    normalized === 'false' ||
    normalized === 'no' ||
    normalized === 'off'
  ) {
    return false;
  }
  return null;
}

setRuntimeCapabilities({ http2: parseBoolean(process.env.OSRV_HTTP2) === true });

await import('../core/{{CORE_JS_NAME}}');

const CONTEXT_DEFAULTS = {
  provider: 'bun',
  runtime: 'bun',
  protocol: 'http',
  httpVersion: '1.1',
};

function toBunTlsValue(value) {
  if (value == null) {
    return null;
  }
  if (typeof value !== 'string') {
    return value;
  }
  if (value.includes('-----BEGIN ')) {
    return value;
  }
  return Bun.file(value);
}

function resolveTlsInputs(options) {
  const tlsInput =
    options.tls && typeof options.tls === 'object' ? options.tls : {};
  const cert =
    tlsInput.cert ?? options.cert ?? process.env.OSRV_TLS_CERT ?? process.env.TLS_CERT ?? null;
  const key =
    tlsInput.key ?? options.key ?? process.env.OSRV_TLS_KEY ?? process.env.TLS_KEY ?? null;
  const passphrase =
    tlsInput.passphrase ??
    options.passphrase ??
    process.env.OSRV_TLS_PASSPHRASE ??
    process.env.TLS_PASSPHRASE ??
    null;

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

function toBunTlsOptions(tlsInputs) {
  if (!tlsInputs) {
    return null;
  }

  return {
    cert: toBunTlsValue(tlsInputs.cert),
    key: toBunTlsValue(tlsInputs.key),
    passphrase: tlsInputs.passphrase,
  };
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
  const tlsInputs = resolveTlsInputs(options);
  const requestedProtocol = String(
    options.protocol ?? process.env.OSRV_PROTOCOL ?? (tlsInputs ? 'https' : 'http'),
  ).toLowerCase();
  const protocol = requestedProtocol === 'https' && tlsInputs ? 'https' : 'http';
  if (requestedProtocol === 'https' && !tlsInputs) {
    console.warn(
      '[osrv/bun] HTTPS requested without TLS cert/key, falling back to HTTP/1.1.',
    );
  }

  const requestedHttp2 = parseBoolean(options.http2 ?? process.env.OSRV_HTTP2) ?? false;
  if (protocol === 'https' && tlsInputs && requestedHttp2) {
    // Reuse the Node-compatible HTTP/2 adapter to avoid duplicate logic in bun runtime template.
    const server = await serveWithNodeHttp2(
      {
        ...options,
        port,
        hostname,
        protocol: 'https',
        tls: tlsInputs,
        mainHandler: main,
      },
      {
        provider: 'bun',
        runtime: 'bun',
        logPrefix: '[osrv/bun]',
        // Bun's node:http2 currently cannot negotiate HTTP/1.1 fallback.
        allowHTTP1: false,
      },
    );
    setRuntimeCapabilities({ http2: true });
    return server;
  }

  const bunTls = protocol === 'https' ? toBunTlsOptions(tlsInputs) : null;
  const server = Bun.serve({
    port,
    hostname,
    development: false,
    reusePort: Boolean(options.reusePort ?? false),
    ...(protocol === 'https' && bunTls ? { tls: bunTls } : {}),
    fetch(request, server) {
      let requestProtocol = protocol;
      try {
        requestProtocol = new URL(request.url).protocol.replace(':', '') || protocol;
      } catch (_) {}
      return dispatch(request, {
        provider: 'bun',
        runtime: 'bun',
        protocol: requestProtocol,
        httpVersion: '1.1',
        tls: requestProtocol === 'https',
        env: {},
        raw: { server },
      });
    },
  });

  setRuntimeCapabilities({ http2: false });
  return server;
}

if (import.meta.main) {
  await serve();
}
