import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createServer as createHttpServer } from 'node:http';
import { createSecureServer as createHttp2SecureServer } from 'node:http2';
import { fileURLToPath } from 'node:url';
import {
  isBridgeHandler,
  isUpgradeBridgeResponse,
  runBridgeHandler,
  waitForMain,
} from '../../shared/bridge.mjs';
import {
  setRuntimeCapabilities,
  toRuntimeEnv,
} from '../../shared/runtime_utils.mjs';
import {
  base64ToBytes,
  bytesToBase64,
  createWebSocketBridge,
} from '../../shared/ws_bridge.mjs';

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
const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const wsBridge = createWebSocketBridge({
  requestIdPrefix: 'node-ws',
  logPrefix: '[osrv/node]',
});

function hasTlsFromEnvironment() {
  const cert = process.env.OSRV_TLS_CERT ?? process.env.TLS_CERT;
  const key = process.env.OSRV_TLS_KEY ?? process.env.TLS_KEY;
  return typeof cert === 'string' && cert.length > 0 && typeof key === 'string' && key.length > 0;
}


function encodeWsFrame(opcode, payload = Buffer.alloc(0)) {
  const length = payload.length;

  if (length < 126) {
    const header = Buffer.alloc(2);
    header[0] = 0x80 | (opcode & 0x0f);
    header[1] = length;
    return Buffer.concat([header, payload]);
  }

  if (length < 65536) {
    const header = Buffer.alloc(4);
    header[0] = 0x80 | (opcode & 0x0f);
    header[1] = 126;
    header.writeUInt16BE(length, 2);
    return Buffer.concat([header, payload]);
  }

  const header = Buffer.alloc(10);
  header[0] = 0x80 | (opcode & 0x0f);
  header[1] = 127;
  header.writeBigUInt64BE(BigInt(length), 2);
  return Buffer.concat([header, payload]);
}

function encodeWsClosePayload(code, reason) {
  const reasonText = typeof reason === 'string' ? reason : '';
  if (!Number.isFinite(code)) {
    return Buffer.from(reasonText, 'utf8');
  }

  const reasonBytes = Buffer.from(reasonText, 'utf8');
  const payload = Buffer.allocUnsafe(2 + reasonBytes.length);
  payload.writeUInt16BE(code, 0);
  reasonBytes.copy(payload, 2);
  return payload;
}

function isWebSocketUpgradeRequest(headers) {
  const upgrade = headers.upgrade;
  if (Array.isArray(upgrade)) {
    return upgrade.some((value) => String(value).toLowerCase() === 'websocket');
  }
  return typeof upgrade === 'string' && upgrade.toLowerCase() === 'websocket';
}

function writeRawUpgradeError(socket, statusCode, message) {
  const body = Buffer.from(message, 'utf8');
  const lines = [
    `HTTP/1.1 ${statusCode} ${httpStatusText(statusCode)}`,
    'content-type: text/plain; charset=utf-8',
    `content-length: ${body.length}`,
    'connection: close',
    '',
    '',
  ];
  socket.write(lines.join('\r\n'));
  if (body.length > 0) {
    socket.write(body);
  }
  socket.end();
}

async function writeRawHttpResponse(socket, response) {
  const body = response.body
    ? Buffer.from(await response.arrayBuffer())
    : Buffer.alloc(0);

  const headerLines = [];
  let hasContentLength = false;
  for (const [key, value] of response.headers) {
    if (HOP_BY_HOP_HEADERS.has(String(key).toLowerCase())) {
      continue;
    }
    if (String(key).toLowerCase() === 'content-length') {
      hasContentLength = true;
    }
    headerLines.push(`${key}: ${value}`);
  }
  if (!hasContentLength) {
    headerLines.push(`content-length: ${body.length}`);
  }
  headerLines.push('connection: close');

  const lines = [
    `HTTP/1.1 ${response.status} ${httpStatusText(response.status)}`,
    ...headerLines,
    '',
    '',
  ];
  socket.write(lines.join('\r\n'));
  if (body.length > 0) {
    socket.write(body);
  }
  socket.end();
}

function httpStatusText(statusCode) {
  switch (statusCode) {
    case 101:
      return 'Switching Protocols';
    case 200:
      return 'OK';
    case 400:
      return 'Bad Request';
    case 426:
      return 'Upgrade Required';
    case 500:
      return 'Internal Server Error';
    default:
      return 'Response';
  }
}

function bindNodeWebSocket(socket, socketId, head) {
  const state = {
    buffer: Buffer.alloc(0),
    closed: false,
    closing: false,
  };

  function finalizeClose(code, reason) {
    if (state.closed) {
      return;
    }

    state.closed = true;
    wsBridge.unregisterConnection(socketId);
    wsBridge.notify('close', socketId, String(code ?? ''), String(reason ?? ''));
  }

  const connection = {
    sendText(text) {
      if (state.closed) {
        return;
      }
      socket.write(encodeWsFrame(0x1, Buffer.from(String(text), 'utf8')));
    },
    sendBinary(bytes) {
      if (state.closed) {
        return;
      }
      socket.write(encodeWsFrame(0x2, Buffer.from(bytes)));
    },
    close(code, reason) {
      if (state.closed || state.closing) {
        return;
      }
      state.closing = true;
      socket.write(encodeWsFrame(0x8, encodeWsClosePayload(code, reason)));
      socket.end();
    },
  };

  function handleFrame(opcode, payload) {
    switch (opcode) {
      case 0x1:
        wsBridge.notify('message', socketId, 'text', payload.toString('utf8'));
        break;
      case 0x2:
        wsBridge.notify('message', socketId, 'binary', bytesToBase64(payload));
        break;
      case 0x8: {
        let code;
        let reason = '';
        if (payload.length >= 2) {
          code = payload.readUInt16BE(0);
          reason = payload.subarray(2).toString('utf8');
        }
        if (!state.closing) {
          socket.write(encodeWsFrame(0x8, encodeWsClosePayload(code, reason)));
        }
        socket.end();
        finalizeClose(code, reason);
        break;
      }
      case 0x9:
        socket.write(encodeWsFrame(0xA, payload));
        break;
      case 0xA:
        break;
      default:
        connection.close(1003, 'Unsupported websocket opcode');
        finalizeClose(1003, 'Unsupported websocket opcode');
        break;
    }
  }

  function parseFrames() {
    while (state.buffer.length >= 2) {
      const first = state.buffer[0];
      const second = state.buffer[1];
      const fin = (first & 0x80) !== 0;
      const opcode = first & 0x0f;
      const masked = (second & 0x80) !== 0;
      let payloadLength = second & 0x7f;
      let offset = 2;

      if (!fin) {
        connection.close(1003, 'Fragmented websocket frames are not supported');
        finalizeClose(1003, 'Fragmented websocket frames are not supported');
        return;
      }

      if (payloadLength === 126) {
        if (state.buffer.length < 4) {
          return;
        }
        payloadLength = state.buffer.readUInt16BE(2);
        offset = 4;
      } else if (payloadLength === 127) {
        if (state.buffer.length < 10) {
          return;
        }
        const extended = state.buffer.readBigUInt64BE(2);
        if (extended > BigInt(Number.MAX_SAFE_INTEGER)) {
          connection.close(1009, 'WebSocket frame too large');
          finalizeClose(1009, 'WebSocket frame too large');
          return;
        }
        payloadLength = Number(extended);
        offset = 10;
      }

      if (!masked) {
        connection.close(1002, 'Client websocket frames must be masked');
        finalizeClose(1002, 'Client websocket frames must be masked');
        return;
      }

      if (state.buffer.length < offset + 4 + payloadLength) {
        return;
      }

      const mask = state.buffer.subarray(offset, offset + 4);
      const payloadStart = offset + 4;
      const payloadEnd = payloadStart + payloadLength;
      const payload = Buffer.from(state.buffer.subarray(payloadStart, payloadEnd));
      for (let i = 0; i < payload.length; i += 1) {
        payload[i] ^= mask[i % 4];
      }
      state.buffer = state.buffer.subarray(payloadEnd);
      handleFrame(opcode, payload);
    }
  }

  socket.on('data', (chunk) => {
    if (state.closed) {
      return;
    }
    state.buffer = Buffer.concat([state.buffer, chunk]);
    try {
      parseFrames();
    } catch (error) {
      wsBridge.notify('error', socketId, String(error));
      connection.close(1011, 'WebSocket frame parse failure');
      finalizeClose(1011, 'WebSocket frame parse failure');
    }
  });

  socket.on('end', () => {
    finalizeClose(1000, '');
  });

  socket.on('close', () => {
    finalizeClose(1000, '');
  });

  socket.on('error', (error) => {
    wsBridge.notify('error', socketId, String(error));
    finalizeClose(1011, String(error));
  });

  if (head && head.length > 0) {
    state.buffer = Buffer.concat([state.buffer, head]);
    parseFrames();
  }

  wsBridge.registerConnection(socketId, connection);
  wsBridge.notify('open', socketId);
  wsBridge.flushPendingCommands(socketId);
}

const presetProtocol = String(process.env.OSRV_PROTOCOL ?? 'http').toLowerCase();
setRuntimeCapabilities({
  http2: presetProtocol === 'https' && hasTlsFromEnvironment(),
  websocket: true,
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
    if (
      normalizeHttpVersion(nodeRes.req?.httpVersion || '1.1') === '2' &&
      HOP_BY_HOP_HEADERS.has(key.toLowerCase())
    ) {
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
        requestId: wsBridge.nextRequestId(),
        localAddress,
        remoteAddress,
        ip: req.socket?.remoteAddress ?? null,
        tls: isTls,
        env: runtimeEnv,
        raw: { req, res },
      });
      if (isUpgradeBridgeResponse(response)) {
        res.statusCode = 426;
        res.end('WebSocket upgrade requires Upgrade: websocket');
        return;
      }
      await writeNodeResponse(res, response);
    } catch (error) {
      res.statusCode = 500;
      res.end('Internal Server Error');
      console.error(`${runtimeConfig.logPrefix} request handling failed`, error);
    }
  };
}

async function handleNodeUpgrade({
  req,
  socket,
  head,
  dispatch,
  hostname,
  port,
  runtimeConfig,
  runtimeEnv,
}) {
  try {
    if (!isWebSocketUpgradeRequest(req.headers)) {
      writeRawUpgradeError(socket, 426, 'Upgrade Required');
      return;
    }

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
    const requestId = wsBridge.nextRequestId();
    const response = await dispatch(request, {
      provider: runtimeConfig.provider,
      runtime: runtimeConfig.runtime,
      protocol: requestProtocol,
      httpVersion: normalizeHttpVersion(req.httpVersion || '1.1'),
      requestId,
      localAddress,
      remoteAddress,
      ip: req.socket?.remoteAddress ?? null,
      tls: isTls,
      env: runtimeEnv,
      raw: { req, socket },
    });

    if (!isUpgradeBridgeResponse(response)) {
      wsBridge.takePendingSocketId(requestId);
      await writeRawHttpResponse(socket, response);
      return;
    }

    const socketId = wsBridge.takePendingSocketId(requestId);
    if (!socketId) {
      writeRawUpgradeError(
        socket,
        500,
        'Missing websocket upgrade binding for status 101 response',
      );
      return;
    }

    const key = req.headers['sec-websocket-key'];
    if (typeof key !== 'string' || key.length === 0) {
      writeRawUpgradeError(socket, 400, 'Missing websocket key');
      return;
    }

    const accept = createHash('sha1')
      .update(key + WS_GUID)
      .digest('base64');

    const lines = [
      'HTTP/1.1 101 Switching Protocols',
      'Upgrade: websocket',
      'Connection: Upgrade',
      `Sec-WebSocket-Accept: ${accept}`,
      '',
      '',
    ];
    socket.write(lines.join('\r\n'));
    bindNodeWebSocket(socket, socketId, head);
  } catch (error) {
    console.error(`${runtimeConfig.logPrefix} websocket upgrade failed`, error);
    if (!socket.destroyed) {
      writeRawUpgradeError(socket, 500, 'Internal Server Error');
    }
  }
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

  if (runtimeConfig.allowHTTP1) {
    server.on('upgrade', (req, socket, head) => {
      void handleNodeUpgrade({
        req,
        socket,
        head,
        dispatch,
        hostname,
        port,
        runtimeConfig,
        runtimeEnv,
      });
    });
  }

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
    setRuntimeCapabilities({ http2: true, websocket: true });
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
  server.on('upgrade', (req, socket, head) => {
    void handleNodeUpgrade({
      req,
      socket,
      head,
      dispatch,
      hostname,
      port,
      runtimeConfig,
      runtimeEnv,
    });
  });

  server.listen(port, hostname);
  setRuntimeCapabilities({ http2: false, websocket: true });
  return server;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  await serve();
}
