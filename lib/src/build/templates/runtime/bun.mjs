import { serveWithNodeHttp2 } from '../node/index.mjs';
import {
  isBridgeHandler,
  isUpgradeBridgeResponse,
  runBridgeHandler,
  waitForMain,
} from '../../shared/bridge.mjs';
import {
  parseBoolean,
  setRuntimeCapabilities,
  toRuntimeEnv,
} from '../../shared/runtime_utils.mjs';
import {
  bytesToBase64,
  createWebSocketBridge,
  isWebSocketUpgradeRequest,
} from '../../shared/ws_bridge.mjs';

if (typeof globalThis.self === 'undefined') {
  globalThis.self = globalThis;
}

setRuntimeCapabilities({
  http2:
    parseBoolean(process.env.OSRV_BUN_HTTP2 ?? process.env.OSRV_HTTP2) ===
    true,
  websocket: true,
});

await import('../core/{{CORE_JS_NAME}}');

const CONTEXT_DEFAULTS = {
  provider: 'bun',
  runtime: 'bun',
  protocol: 'http',
  httpVersion: '1.1',
};

const wsBridge = createWebSocketBridge({
  requestIdPrefix: 'bun-ws',
  logPrefix: '[osrv/bun]',
});

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
    tlsInput.cert ??
    options.cert ??
    process.env.OSRV_TLS_CERT ??
    process.env.TLS_CERT ??
    null;
  const key =
    tlsInput.key ??
    options.key ??
    process.env.OSRV_TLS_KEY ??
    process.env.TLS_KEY ??
    null;
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
    passphrase:
      typeof passphrase === 'string' && passphrase.length > 0
        ? passphrase
        : undefined,
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

function toConnection(ws) {
  return {
    sendText(text) {
      ws.send(String(text));
    },
    sendBinary(bytes) {
      ws.send(bytes);
    },
    close(code, reason) {
      if (Number.isFinite(code)) {
        ws.close(code, reason);
      } else {
        ws.close();
      }
    },
  };
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
  const hostname = String(
    options.hostname ?? process.env.HOSTNAME ?? '0.0.0.0',
  );
  const runtimeEnv = toRuntimeEnv(process.env);
  const tlsInputs = resolveTlsInputs(options);
  const requestedProtocol = String(
    options.protocol ??
      process.env.OSRV_PROTOCOL ??
      (tlsInputs ? 'https' : 'http'),
  ).toLowerCase();
  const protocol = requestedProtocol === 'https' && tlsInputs ? 'https' : 'http';
  if (requestedProtocol === 'https' && !tlsInputs) {
    console.warn(
      '[osrv/bun] HTTPS requested without TLS cert/key, falling back to HTTP/1.1.',
    );
  }

  const requestedHttp2 =
    parseBoolean(
      options.http2 ?? process.env.OSRV_BUN_HTTP2 ?? process.env.OSRV_HTTP2,
    ) ?? false;
  if (requestedHttp2 && protocol !== 'https') {
    console.warn(
      '[osrv/bun] HTTP/2 requested without HTTPS/TLS, falling back to HTTP/1.1.',
    );
  }
  if (protocol === 'https' && tlsInputs && requestedHttp2) {
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
        allowHTTP1: false,
      },
    );
    setRuntimeCapabilities({ http2: true, websocket: false });
    return server;
  }

  const bunTls = protocol === 'https' ? toBunTlsOptions(tlsInputs) : null;
  const server = Bun.serve({
    port,
    hostname,
    development: false,
    reusePort: Boolean(options.reusePort ?? false),
    ...(protocol === 'https' && bunTls ? { tls: bunTls } : {}),
    websocket: {
      open(ws) {
        const socketId = String(ws.data?.socketId ?? '');
        if (socketId.length === 0) {
          ws.close(1011, 'Missing socket id');
          return;
        }

        wsBridge.registerConnection(socketId, toConnection(ws));
        wsBridge.notify('open', socketId);
        wsBridge.flushPendingCommands(socketId);
      },
      message(ws, message) {
        const socketId = String(ws.data?.socketId ?? '');
        if (socketId.length === 0) {
          return;
        }

        if (typeof message === 'string') {
          wsBridge.notify('message', socketId, 'text', message);
          return;
        }

        if (message instanceof Uint8Array) {
          wsBridge.notify('message', socketId, 'binary', bytesToBase64(message));
          return;
        }

        if (message instanceof ArrayBuffer) {
          wsBridge.notify(
            'message',
            socketId,
            'binary',
            bytesToBase64(new Uint8Array(message)),
          );
          return;
        }

        if (ArrayBuffer.isView(message)) {
          wsBridge.notify(
            'message',
            socketId,
            'binary',
            bytesToBase64(
              new Uint8Array(
                message.buffer,
                message.byteOffset,
                message.byteLength,
              ),
            ),
          );
        }
      },
      close(ws, code, reason) {
        const socketId = String(ws.data?.socketId ?? '');
        if (socketId.length === 0) {
          return;
        }

        wsBridge.unregisterConnection(socketId);
        wsBridge.notify('close', socketId, String(code ?? ''), String(reason ?? ''));
      },
      drain() {},
    },
    async fetch(request, runtimeServer) {
      let requestProtocol = protocol;
      try {
        requestProtocol =
          new URL(request.url).protocol.replace(':', '') || protocol;
      } catch (_) {}

      const requestId = wsBridge.nextRequestId();
      const response = await dispatch(request, {
        provider: 'bun',
        runtime: 'bun',
        protocol: requestProtocol,
        httpVersion: '1.1',
        requestId,
        tls: requestProtocol === 'https',
        env: runtimeEnv,
        raw: { server: runtimeServer, requestId },
      });

      if (isUpgradeBridgeResponse(response)) {
        const socketId = wsBridge.takePendingSocketId(requestId);

        if (!isWebSocketUpgradeRequest(request)) {
          return new Response('WebSocket upgrade requires Upgrade: websocket', {
            status: 426,
          });
        }
        if (!socketId) {
          return new Response('Missing websocket upgrade binding', {
            status: 500,
          });
        }

        const upgraded = runtimeServer.upgrade(request, {
          data: { socketId },
        });
        if (!upgraded) {
          return new Response('WebSocket upgrade failed', { status: 500 });
        }
        return;
      }

      wsBridge.takePendingSocketId(requestId);
      return response;
    },
  });

  setRuntimeCapabilities({ http2: false, websocket: true });
  return server;
}

if (import.meta.main) {
  await serve();
}
