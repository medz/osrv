import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';
import { isBridgeHandler, runBridgeHandler, waitForMain } from '../../shared/bridge.mjs';

if (typeof globalThis.self === 'undefined') {
  globalThis.self = globalThis;
}
await import('../core/{{CORE_JS_NAME}}');

const CONTEXT_DEFAULTS = {
  provider: 'node',
  runtime: 'node',
  protocol: 'http',
  httpVersion: '1.1',
};
const BODY_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

function toFetchRequest(nodeReq, { hostname, port, protocol }) {
  const origin = protocol + '://' + hostname + ':' + port;
  const url = new URL(nodeReq.url || '/', origin);
  const method = (nodeReq.method || 'GET').toUpperCase();
  const init = { method, headers: nodeReq.headers };
  if (BODY_METHODS.has(method)) {
    init.body = nodeReq;
    init.duplex = 'half';
  }
  return new Request(url, init);
}

async function writeNodeResponse(nodeRes, response) {
  nodeRes.statusCode = response.status;
  for (const [key, value] of response.headers) {
    nodeRes.setHeader(key, value);
  }
  if (response.body) {
    const bytes = Buffer.from(await response.arrayBuffer());
    nodeRes.end(bytes);
    return;
  }
  nodeRes.end();
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
  const protocol = String(options.protocol ?? process.env.OSRV_PROTOCOL ?? 'http');

  const server = createServer(async (req, res) => {
    try {
      const request = toFetchRequest(req, { hostname, port, protocol });
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
        provider: 'node',
        runtime: 'node',
        protocol,
        httpVersion: req.httpVersion || '1.1',
        localAddress,
        remoteAddress,
        ip: req.socket?.remoteAddress ?? null,
        tls: protocol === 'https',
        env: {},
        raw: { req, res },
      });
      await writeNodeResponse(res, response);
    } catch (error) {
      res.statusCode = 500;
      res.end('Internal Server Error');
      console.error('[osrv/node] request handling failed', error);
    }
  });

  server.listen(port, hostname);
  return server;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  await serve();
}
