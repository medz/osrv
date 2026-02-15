import {
  isBridgeHandler,
  isUpgradeBridgeResponse,
  runBridgeHandler,
  waitForMain,
} from '../../shared/bridge.mjs';
import { setRuntimeCapabilities } from '../../shared/runtime_utils.mjs';
import {
  bytesToBase64,
  createWebSocketBridge,
  isWebSocketUpgradeRequest,
} from '../../shared/ws_bridge.mjs';

if (typeof globalThis.self === 'undefined') {
  globalThis.self = globalThis;
}

const supportsWebSocketUpgrade =
  typeof Deno !== 'undefined' && typeof Deno.upgradeWebSocket === 'function';
setRuntimeCapabilities({
  http2: true,
  websocket: supportsWebSocketUpgrade,
});

await import('../core/{{CORE_JS_NAME}}');

const CONTEXT_DEFAULTS = {
  provider: 'deno',
  runtime: 'deno',
  protocol: 'http',
  httpVersion: '1.1',
};

const wsBridge = createWebSocketBridge({
  requestIdPrefix: 'deno-ws',
  logPrefix: '[osrv/deno]',
});

function readRuntimeEnv() {
  try {
    if (typeof Deno?.env?.toObject === 'function') {
      return Deno.env.toObject();
    }
  } catch (_) {
    // `--allow-env` is optional for serving; missing permission should not crash requests.
  }
  return {};
}

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
    tlsInput.cert ??
    options.cert ??
    Deno.env.get('OSRV_TLS_CERT') ??
    Deno.env.get('TLS_CERT');
  const keyInput =
    tlsInput.key ??
    options.key ??
    Deno.env.get('OSRV_TLS_KEY') ??
    Deno.env.get('TLS_KEY');
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
  if (!addr || typeof addr !== 'object') {
    return null;
  }
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

function bindDenoSocket(socket, socketId) {
  const state = { closed: false };
  const connection = {
    sendText(text) {
      if (state.closed) {
        return;
      }
      socket.send(String(text));
    },
    sendBinary(bytes) {
      if (state.closed) {
        return;
      }
      socket.send(bytes);
    },
    close(code, reason) {
      if (state.closed) {
        return;
      }
      state.closed = true;
      if (Number.isFinite(code)) {
        socket.close(code, reason);
      } else {
        socket.close();
      }
    },
  };

  wsBridge.registerConnection(socketId, connection);

  socket.addEventListener('open', () => {
    wsBridge.notify('open', socketId);
    wsBridge.flushPendingCommands(socketId);
  });
  socket.addEventListener('message', (event) => {
    const data = event.data;
    if (typeof data === 'string') {
      wsBridge.notify('message', socketId, 'text', data);
      return;
    }
    if (data instanceof Uint8Array) {
      wsBridge.notify('message', socketId, 'binary', bytesToBase64(data));
      return;
    }
    if (data instanceof ArrayBuffer) {
      wsBridge.notify(
        'message',
        socketId,
        'binary',
        bytesToBase64(new Uint8Array(data)),
      );
      return;
    }
    if (ArrayBuffer.isView(data)) {
      wsBridge.notify(
        'message',
        socketId,
        'binary',
        bytesToBase64(
          new Uint8Array(data.buffer, data.byteOffset, data.byteLength),
        ),
      );
    }
  });
  socket.addEventListener('close', (event) => {
    state.closed = true;
    wsBridge.unregisterConnection(socketId);
    wsBridge.notify(
      'close',
      socketId,
      String(event?.code ?? ''),
      String(event?.reason ?? ''),
    );
  });
  socket.addEventListener('error', (event) => {
    wsBridge.notify('error', socketId, String(event?.message ?? 'socket error'));
  });
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
  const runtimeEnv = readRuntimeEnv();
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
    async (request, info) => {
      let requestProtocol = protocol;
      try {
        requestProtocol =
          new URL(request.url).protocol.replace(':', '') || protocol;
      } catch (_) {}

      const requestId = wsBridge.nextRequestId();
      const response = await dispatch(request, {
        provider: 'deno',
        runtime: 'deno',
        protocol: requestProtocol,
        httpVersion: '1.1',
        requestId,
        localAddress: formatAddr(info?.localAddr),
        remoteAddress: formatAddr(info?.remoteAddr),
        ip: info?.remoteAddr?.hostname ?? null,
        tls: requestProtocol === 'https',
        env: runtimeEnv,
        raw: { info, requestId },
      });

      if (isUpgradeBridgeResponse(response)) {
        const socketId = wsBridge.takePendingSocketId(requestId);

        if (!isWebSocketUpgradeRequest(request)) {
          return new Response('WebSocket upgrade requires Upgrade: websocket', {
            status: 426,
          });
        }
        if (!supportsWebSocketUpgrade) {
          return new Response(
            'WebSocket upgrade is not available in this Deno runtime.',
            { status: 501 },
          );
        }
        if (!socketId) {
          return new Response('Missing websocket upgrade binding', {
            status: 500,
          });
        }

        const upgraded = Deno.upgradeWebSocket(request);
        bindDenoSocket(upgraded.socket, socketId);
        return upgraded.response;
      }

      wsBridge.takePendingSocketId(requestId);
      return response;
    },
  );

  setRuntimeCapabilities({ http2: true, websocket: supportsWebSocketUpgrade });
  return server;
}

if (import.meta.main) {
  await serve();
}
