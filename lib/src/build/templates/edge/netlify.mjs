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

const supportsDenoUpgrade =
  typeof Deno !== 'undefined' && typeof Deno.upgradeWebSocket === 'function';
const supportsWebSocketPair = typeof WebSocketPair === 'function';
const supportsWebSocket = supportsDenoUpgrade || supportsWebSocketPair;
setRuntimeCapabilities({ websocket: supportsWebSocket });

await import('../../js/core/{{CORE_JS_NAME}}');

const CONTEXT_DEFAULTS = {
  provider: 'netlify',
  runtime: 'netlify',
  protocol: 'http',
  httpVersion: '1.1',
};

const wsBridge = createWebSocketBridge({
  requestIdPrefix: 'netlify-ws',
  logPrefix: '[osrv/netlify]',
});

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
    provider: 'netlify',
    runtime: 'netlify',
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

function bindPairSocket(socket, socketId) {
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
  } catch (_) {}
  wsBridge.notify('open', socketId);
  wsBridge.flushPendingCommands(socketId);
}

async function runMain(request, normalized) {
  const main = await waitForMain();
  if (typeof main !== 'function') {
    return new Response('globalThis.__osrv_main__ is not set.', { status: 500 });
  }

  if (isBridgeHandler(main)) {
    return runBridgeHandler(main, request, normalized, CONTEXT_DEFAULTS);
  }
  return main(request, normalized);
}

export default async (request, context) => {
  const requestId = wsBridge.nextRequestId();
  const normalized = buildContext(request, context, requestId);
  const response = await runMain(request, normalized);

  if (isUpgradeBridgeResponse(response)) {
    const socketId = wsBridge.takePendingSocketId(requestId);

    if (!isWebSocketUpgradeRequest(request)) {
      return new Response('WebSocket upgrade requires Upgrade: websocket', {
        status: 426,
      });
    }
    if (!socketId) {
      return new Response('Missing websocket upgrade binding', { status: 500 });
    }

    if (supportsDenoUpgrade) {
      const upgraded = Deno.upgradeWebSocket(request);
      bindDenoSocket(upgraded.socket, socketId);
      return upgraded.response;
    }

    if (supportsWebSocketPair) {
      const pair = new WebSocketPair();
      const client = pair[0];
      const server = pair[1];
      bindPairSocket(server, socketId);
      return new Response(null, { status: 101, webSocket: client });
    }

    return new Response(
      'WebSocket upgrade is not available in this Netlify edge runtime.',
      { status: 501 },
    );
  }

  wsBridge.takePendingSocketId(requestId);
  return response;
};
