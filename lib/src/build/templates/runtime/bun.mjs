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

setRuntimeCapabilities({ http2: false });

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

  const cert = toBunTlsValue(certInput);
  const key = toBunTlsValue(keyInput);
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
      '[osrv/bun] HTTPS requested without TLS cert/key, falling back to HTTP/1.1.',
    );
  }

  const server = Bun.serve({
    port,
    hostname,
    development: false,
    reusePort: Boolean(options.reusePort ?? false),
    ...(protocol === 'https' && tls ? { tls } : {}),
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

  setRuntimeCapabilities({
    http2: false,
  });
  return server;
}

if (import.meta.main) {
  await serve();
}
