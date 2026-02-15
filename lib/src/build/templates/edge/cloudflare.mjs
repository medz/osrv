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

const supportsWebSocketPair = typeof WebSocketPair === 'function';
setRuntimeCapabilities({ websocket: supportsWebSocketPair });

await import('../../js/core/{{CORE_JS_NAME}}');

const CONTEXT_DEFAULTS = {
  provider: 'cloudflare',
  runtime: 'cloudflare',
  protocol: 'http',
  httpVersion: '1.1',
};

const wsBridge = createWebSocketBridge({
  requestIdPrefix: 'cloudflare-ws',
  logPrefix: '[osrv/cloudflare]',
});

function normalizeEnv(env) {
  if (env && typeof env === 'object') {
    return env;
  }
  return {};
}

function buildContext(request, env, ctx, requestId) {
  let protocol = 'http';
  try {
    protocol = new URL(request.url).protocol.replace(':', '') || 'http';
  } catch (_) {}
  const ip = request.headers.get('cf-connecting-ip');
  return {
    provider: 'cloudflare',
    runtime: 'cloudflare',
    protocol,
    httpVersion: '1.1',
    requestId,
    tls: protocol === 'https',
    ip: ip || null,
    env: normalizeEnv(env),
    waitUntil: (promise) => ctx?.waitUntil?.(promise),
    ctx,
    raw: { env, ctx, requestId },
  };
}

function bindCloudflareSocket(socket, socketId) {
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
      socket.close(code, reason);
    },
  };

  wsBridge.registerConnection(socketId, connection);

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

  try {
    socket.accept();
  } catch (error) {
    wsBridge.notify('error', socketId, String(error));
  }
  wsBridge.notify('open', socketId);
  wsBridge.flushPendingCommands(socketId);
}

async function handle(request, context) {
  const main = await waitForMain();
  if (typeof main !== 'function') {
    return new Response('globalThis.__osrv_main__ is not set.', { status: 500 });
  }
  if (isBridgeHandler(main)) {
    return runBridgeHandler(main, request, context, CONTEXT_DEFAULTS);
  }
  return main(request, context);
}

export default {
  async fetch(request, env, ctx) {
    const requestId = wsBridge.nextRequestId();
    const context = buildContext(request, env, ctx, requestId);
    const response = await handle(request, context);

    if (isUpgradeBridgeResponse(response)) {
      const socketId = wsBridge.takePendingSocketId(requestId);

      if (!supportsWebSocketPair) {
        return new Response(
          'WebSocket upgrade is not available in this Cloudflare runtime.',
          { status: 501 },
        );
      }
      if (!isWebSocketUpgradeRequest(request)) {
        return new Response('WebSocket upgrade requires Upgrade: websocket', {
          status: 426,
        });
      }
      if (!socketId) {
        return new Response('Missing websocket upgrade binding', { status: 500 });
      }

      const pair = new WebSocketPair();
      const client = pair[0];
      const server = pair[1];
      bindCloudflareSocket(server, socketId);
      return new Response(null, { status: 101, webSocket: client });
    }

    wsBridge.takePendingSocketId(requestId);
    return response;
  },
};
