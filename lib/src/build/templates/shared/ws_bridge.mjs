const WS_ON_PREFIX = '__osrv_ws_on_';

export function bytesToBase64(bytes) {
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

export function base64ToBytes(base64) {
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

export function isWebSocketUpgradeRequest(request) {
  const upgrade = request.headers.get('upgrade');
  return typeof upgrade === 'string' && upgrade.toLowerCase() === 'websocket';
}

export function createWebSocketBridge({
  requestIdPrefix = 'ws',
  logPrefix = '[osrv/ws]',
} = {}) {
  const pendingByRequestId = new Map();
  const connectionsBySocketId = new Map();
  const pendingCommandsBySocketId = new Map();
  let requestSequence = 0;

  function nextRequestId() {
    requestSequence += 1;
    return `${requestIdPrefix}-req-${requestSequence}`;
  }

  function callbackName(kind) {
    return `${WS_ON_PREFIX}${kind}__`;
  }

  function notify(kind, ...args) {
    const callback = globalThis[callbackName(kind)];
    if (typeof callback !== 'function') {
      return;
    }

    try {
      callback(...args);
    } catch (error) {
      console.error(`${logPrefix} websocket callback failed`, error);
    }
  }

  function queueCommand(socketId, command) {
    const queue = pendingCommandsBySocketId.get(socketId);
    if (queue) {
      queue.push(command);
      return;
    }
    pendingCommandsBySocketId.set(socketId, [command]);
  }

  function processCommand(command) {
    if (!command || typeof command !== 'object') {
      return;
    }

    const socketId = String(command.socketId ?? '');
    if (socketId.length === 0) {
      return;
    }

    const connection = connectionsBySocketId.get(socketId);
    if (!connection) {
      queueCommand(socketId, command);
      return;
    }

    const action = String(command.action ?? '');
    switch (action) {
      case 'text':
        connection.sendText(String(command.text ?? ''));
        break;
      case 'binary': {
        const encoded = String(command.bytesBase64 ?? '');
        connection.sendBinary(base64ToBytes(encoded));
        break;
      }
      case 'close': {
        const code = Number(command.code);
        const reason =
          command.reason == null ? undefined : String(command.reason);
        connection.close(Number.isFinite(code) ? code : undefined, reason);
        break;
      }
      default:
        throw new Error(`Unsupported websocket action: ${action}`);
    }
  }

  function flushPendingCommands(socketId) {
    const queue = pendingCommandsBySocketId.get(socketId);
    if (!queue || queue.length === 0) {
      pendingCommandsBySocketId.delete(socketId);
      return;
    }

    pendingCommandsBySocketId.delete(socketId);
    for (const command of queue) {
      processCommand(command);
    }
  }

  function registerPendingUpgrade(requestId, socketId) {
    const id = String(requestId ?? '');
    const wsId = String(socketId ?? '');
    if (id.length === 0 || wsId.length === 0) {
      return false;
    }

    pendingByRequestId.set(id, wsId);
    return true;
  }

  function takePendingSocketId(requestId) {
    const socketId = pendingByRequestId.get(requestId);
    pendingByRequestId.delete(requestId);
    return socketId ?? null;
  }

  function registerConnection(socketId, connection) {
    connectionsBySocketId.set(socketId, connection);
  }

  function unregisterConnection(socketId) {
    connectionsBySocketId.delete(socketId);
    pendingCommandsBySocketId.delete(socketId);
  }

  globalThis.__osrv_ws_register_pending__ = registerPendingUpgrade;
  globalThis.__osrv_ws_send__ = (commandJson, resolve, reject) => {
    try {
      const command =
        typeof commandJson === 'string' ? JSON.parse(commandJson) : commandJson;
      processCommand(command);
      if (typeof resolve === 'function') {
        resolve(true);
      }
    } catch (error) {
      if (typeof reject === 'function') {
        reject(String(error));
      }
    }
  };

  return {
    nextRequestId,
    notify,
    registerPendingUpgrade,
    takePendingSocketId,
    registerConnection,
    unregisterConnection,
    flushPendingCommands,
  };
}
