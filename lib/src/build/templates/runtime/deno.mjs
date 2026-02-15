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

// Deno.serve has built-in HTTP/1.1 + HTTP/2 support.
setRuntimeCapabilities({ http2: true });

await import('../core/{{CORE_JS_NAME}}');

const CONTEXT_DEFAULTS = {
  provider: 'deno',
  runtime: 'deno',
  protocol: 'http',
  httpVersion: '1.1',
};

function readPemOrFile(value) {
  if (typeof value !== 'string' || value.length === 0) {
    return null;
  }
  if (value.includes('-----BEGIN ')) {
    return value;
  }
  return Deno.readTextFileSync(value);
}

function resolveTlsOptions(options) {
  const tlsInput =
    options.tls && typeof options.tls === 'object' ? options.tls : {};
  const certInput =
    tlsInput.cert ?? options.cert ?? Deno.env.get('OSRV_TLS_CERT') ?? Deno.env.get('TLS_CERT');
  const keyInput =
    tlsInput.key ?? options.key ?? Deno.env.get('OSRV_TLS_KEY') ?? Deno.env.get('TLS_KEY');
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

  return { cert, key };
}

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
  const tls = resolveTlsOptions(options);
  const requestedProtocol = String(
    options.protocol ?? Deno.env.get('OSRV_PROTOCOL') ?? (tls ? 'https' : 'http'),
  ).toLowerCase();
  const protocol = requestedProtocol === 'https' && tls ? 'https' : 'http';
  if (requestedProtocol === 'https' && !tls) {
    console.warn(
      '[osrv/deno] HTTPS requested without TLS cert/key, falling back to HTTP/1.1.',
    );
  }

  const server = Deno.serve(
    {
      port,
      hostname,
      ...(protocol === 'https' && tls ? { cert: tls.cert, key: tls.key } : {}),
    },
    (request, info) => {
      let requestProtocol = protocol;
      try {
        requestProtocol = new URL(request.url).protocol.replace(':', '') || protocol;
      } catch (_) {}
      return dispatch(request, {
        provider: 'deno',
        runtime: 'deno',
        protocol: requestProtocol,
        httpVersion: '1.1',
        localAddress: formatAddr(info?.localAddr),
        remoteAddress: formatAddr(info?.remoteAddr),
        ip: info?.remoteAddr?.hostname ?? null,
        tls: requestProtocol === 'https',
        env: {},
        raw: { info },
      });
    },
  );

  setRuntimeCapabilities({ http2: true });
  return server;
}

if (import.meta.main) {
  await serve();
}
