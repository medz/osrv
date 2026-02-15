import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

const String _defaultEntry = 'server.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addCommand('serve')
    ..addCommand('build');

  parser.commands['serve']!
    ..addOption(
      'entry',
      defaultsTo: _defaultEntry,
      help: 'Dart entry file. Defaults to `server.dart`.',
    )
    ..addOption('port', help: 'Port to listen on.')
    ..addOption('hostname', help: 'Hostname to bind to.')
    ..addOption(
      'protocol',
      allowed: <String>['http', 'https'],
      help: 'Protocol preference.',
    )
    ..addOption(
      'config',
      defaultsTo: 'osrv.config.dart',
      help: 'Config file path.',
    )
    ..addFlag('silent', defaultsTo: false, help: 'Silence osrv CLI logs.');

  parser.commands['build']!
    ..addOption(
      'entry',
      defaultsTo: _defaultEntry,
      help: 'Dart entry file to compile. Defaults to `server.dart`.',
    )
    ..addOption('out-dir', defaultsTo: 'dist', help: 'Build output directory.')
    ..addFlag(
      'silent',
      defaultsTo: false,
      help: 'Silence build progress logs.',
    );

  ArgResults result;
  try {
    result = parser.parse(args);
  } on FormatException catch (error) {
    stderr.writeln('[osrv] ${error.message}');
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  final command = result.command;
  if (command == null) {
    stdout.writeln('osrv commands:');
    stdout.writeln(parser.usage);
    return;
  }

  switch (command.name) {
    case 'serve':
      await _runServe(command);
      return;
    case 'build':
      await _runBuild(command);
      return;
    default:
      stderr.writeln('[osrv] unknown command: ${command.name}');
      exitCode = 64;
      return;
  }
}

Future<void> _runServe(ArgResults command) async {
  final entry = _resolveEntry(command['entry'] as String);
  if (entry == null) {
    stderr.writeln(
      '[osrv] entry not found. looked for `${command['entry']}` '
      'and fallback `bin/server.dart`.',
    );
    exitCode = 66;
    return;
  }

  final configPath = command['config'] as String;
  final fileConfig = await _loadConfigFile(configPath);
  final env = Platform.environment;

  final port =
      _firstNonEmpty(
        command['port'] as String?,
        env['PORT'],
        env['OSRV_PORT'],
      ) ??
      fileConfig.port ??
      '3000';

  final hostname =
      _firstNonEmpty(
        command['hostname'] as String?,
        env['HOSTNAME'],
        env['OSRV_HOSTNAME'],
      ) ??
      fileConfig.hostname ??
      '0.0.0.0';

  final protocol =
      _firstNonEmpty(command['protocol'] as String?, env['OSRV_PROTOCOL']) ??
      fileConfig.protocol ??
      'http';

  final spawnedEnv = <String, String>{
    ...env,
    'PORT': port,
    'HOSTNAME': hostname,
    'OSRV_PORT': port,
    'OSRV_HOSTNAME': hostname,
    'OSRV_PROTOCOL': protocol,
  };

  if (!(command['silent'] as bool)) {
    stdout.writeln(
      '[osrv] serving `$entry` with PORT=$port HOSTNAME=$hostname PROTOCOL=$protocol',
    );
  }

  final child = await Process.start(
    'dart',
    <String>['run', entry],
    mode: ProcessStartMode.inheritStdio,
    environment: spawnedEnv,
  );

  exitCode = await child.exitCode;
}

Future<void> _runBuild(ArgResults command) async {
  final entry = _resolveEntry(command['entry'] as String);
  if (entry == null) {
    stderr.writeln(
      '[osrv] entry not found. looked for `${command['entry']}` '
      'and fallback `bin/server.dart`.',
    );
    exitCode = 66;
    return;
  }

  final outDir = command['out-dir'] as String;
  final silent = command['silent'] as bool;
  final baseName = _basenameWithoutExtension(entry);

  _ensureDir('$outDir/js/core');
  _ensureDir('$outDir/js/node');
  _ensureDir('$outDir/js/bun');
  _ensureDir('$outDir/js/deno');
  _ensureDir('$outDir/edge/cloudflare');
  _ensureDir('$outDir/edge/vercel');
  _ensureDir('$outDir/edge/netlify');
  _ensureDir('$outDir/bin');

  final coreJsName = '$baseName.js';
  final coreJsPath = '$outDir/js/core/$coreJsName';
  final exeName = Platform.isWindows ? '$baseName.exe' : baseName;
  final exePath = '$outDir/bin/$exeName';

  await _run('dart', <String>[
    'compile',
    'js',
    entry,
    '-o',
    coreJsPath,
  ], silent: silent);

  await _run('dart', <String>[
    'compile',
    'exe',
    entry,
    '-o',
    exePath,
  ], silent: silent);

  _writeRuntimeWrappers(
    outDir,
    coreJsName: coreJsName,
  );

  if (!silent) {
    stdout.writeln('[osrv] build complete');
    stdout.writeln('[osrv] js core: $coreJsPath');
    stdout.writeln('[osrv] exe: $exePath');
  }
}

void _writeRuntimeWrappers(
  String outDir, {
  required String coreJsName,
}) {
  File('$outDir/js/node/index.mjs').writeAsStringSync('''
import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';

if (typeof globalThis.self === 'undefined') {
  globalThis.self = globalThis;
}
await import('../core/$coreJsName');

const BODY_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);
const BRIDGE_MODE = 'json-v1';

function bytesToBase64(bytes) {
  return Buffer.from(bytes).toString('base64');
}

function base64ToBytes(base64) {
  return new Uint8Array(Buffer.from(base64, 'base64'));
}

function normalizeRuntimeContext(input = {}) {
  const value = input && typeof input === 'object' ? input : {};
  const env =
    value.env && typeof value.env === 'object' && value.env !== null
      ? value.env
      : {};
  const protocol = typeof value.protocol === 'string' ? value.protocol : 'http';
  return {
    provider: typeof value.provider === 'string' ? value.provider : 'node',
    runtime: typeof value.runtime === 'string' ? value.runtime : 'node',
    protocol,
    httpVersion:
      typeof value.httpVersion === 'string' ? value.httpVersion : '1.1',
    localAddress:
      typeof value.localAddress === 'string' ? value.localAddress : null,
    remoteAddress:
      typeof value.remoteAddress === 'string' ? value.remoteAddress : null,
    ip: typeof value.ip === 'string' ? value.ip : null,
    tls: Boolean(value.tls ?? protocol === 'https'),
    env,
  };
}

async function serializeRequest(request) {
  const headers = [];
  for (const [name, value] of request.headers.entries()) {
    headers.push([name, value]);
  }

  const method = (request.method || 'GET').toUpperCase();
  let bodyBase64 = null;
  if (BODY_METHODS.has(method)) {
    const clone = request.clone();
    const buffer = await clone.arrayBuffer();
    if (buffer.byteLength > 0) {
      bodyBase64 = bytesToBase64(new Uint8Array(buffer));
    }
  }

  return {
    url: request.url,
    method,
    headers,
    bodyBase64,
  };
}

function responseFromBridgePayload(responsePayload) {
  const payload =
    typeof responsePayload === 'string'
      ? JSON.parse(responsePayload)
      : responsePayload;
  if (!payload || typeof payload !== 'object') {
    throw new Error('Invalid bridge response payload.');
  }

  const status = Number(payload.status ?? 500);
  const headers = new Headers();
  if (Array.isArray(payload.headers)) {
    for (const entry of payload.headers) {
      if (Array.isArray(entry) && entry.length >= 2) {
        headers.append(String(entry[0]), String(entry[1]));
      }
    }
  }

  let body = null;
  if (typeof payload.bodyBase64 === 'string' && payload.bodyBase64.length > 0) {
    body = base64ToBytes(payload.bodyBase64);
  }

  return new Response(body, { status, headers });
}

async function waitForMain(timeoutMs = 5000) {
  const startedAt = Date.now();
  while (Date.now() - startedAt <= timeoutMs) {
    const handler = globalThis.__osrv_main__;
    if (typeof handler === 'function') {
      return handler;
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  return null;
}

function isBridgeHandler(handler) {
  return (
    typeof handler === 'function' &&
    handler.__osrv_bridge__ === BRIDGE_MODE
  );
}

async function runBridgeHandler(handler, request, context = {}) {
  const payload = JSON.stringify({
    request: await serializeRequest(request),
    runtime: normalizeRuntimeContext(context),
    context: {},
  });
  const result = await new Promise((resolve, reject) => {
    try {
      handler(payload, resolve, reject);
    } catch (error) {
      reject(error);
    }
  });
  return responseFromBridgePayload(result);
}

async function handle(request, context = {}) {
  const handler = globalThis.__osrv_main__;
  if (typeof handler !== 'function') {
    throw new Error(
      'globalThis.__osrv_main__ is not set. Ensure your Dart entry calls server.serve() and rebuild with `dart run osrv build`.',
    );
  }

  if (isBridgeHandler(handler)) {
    return runBridgeHandler(handler, request, context);
  }
  return await handler(request, context);
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

function serveWithMain(options) {
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
      const response = await handle(request, {
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

export async function serve(options = {}) {
  const handler = await waitForMain();
  if (typeof handler !== 'function') {
    throw new Error(
      'globalThis.__osrv_main__ is not set. Build output expects Dart JS core to register handler. Check dist/js/core/$coreJsName.',
    );
  }
  return serveWithMain(options);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  await serve();
}
''');

  File('$outDir/js/bun/index.mjs').writeAsStringSync('''
if (typeof globalThis.self === 'undefined') {
  globalThis.self = globalThis;
}
await import('../core/$coreJsName');

const BODY_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);
const BRIDGE_MODE = 'json-v1';

function bytesToBase64(bytes) {
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

function base64ToBytes(base64) {
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

async function waitForMain(timeoutMs = 5000) {
  const startedAt = Date.now();
  while (Date.now() - startedAt <= timeoutMs) {
    const handler = globalThis.__osrv_main__;
    if (typeof handler === 'function') {
      return handler;
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  return null;
}

function isBridgeHandler(handler) {
  return (
    typeof handler === 'function' &&
    handler.__osrv_bridge__ === BRIDGE_MODE
  );
}

function normalizeRuntimeContext(input = {}) {
  const value = input && typeof input === 'object' ? input : {};
  const env =
    value.env && typeof value.env === 'object' && value.env !== null
      ? value.env
      : {};
  const protocol = typeof value.protocol === 'string' ? value.protocol : 'http';
  return {
    provider: typeof value.provider === 'string' ? value.provider : 'bun',
    runtime: typeof value.runtime === 'string' ? value.runtime : 'bun',
    protocol,
    httpVersion:
      typeof value.httpVersion === 'string' ? value.httpVersion : '1.1',
    localAddress:
      typeof value.localAddress === 'string' ? value.localAddress : null,
    remoteAddress:
      typeof value.remoteAddress === 'string' ? value.remoteAddress : null,
    ip: typeof value.ip === 'string' ? value.ip : null,
    tls: Boolean(value.tls ?? protocol === 'https'),
    env,
  };
}

async function serializeRequest(request) {
  const headers = [];
  for (const [name, value] of request.headers.entries()) {
    headers.push([name, value]);
  }

  const method = (request.method || 'GET').toUpperCase();
  let bodyBase64 = null;
  if (BODY_METHODS.has(method)) {
    const clone = request.clone();
    const buffer = await clone.arrayBuffer();
    if (buffer.byteLength > 0) {
      bodyBase64 = bytesToBase64(new Uint8Array(buffer));
    }
  }

  return {
    url: request.url,
    method,
    headers,
    bodyBase64,
  };
}

function responseFromBridgePayload(responsePayload) {
  const payload =
    typeof responsePayload === 'string'
      ? JSON.parse(responsePayload)
      : responsePayload;
  if (!payload || typeof payload !== 'object') {
    throw new Error('Invalid bridge response payload.');
  }

  const status = Number(payload.status ?? 500);
  const headers = new Headers();
  if (Array.isArray(payload.headers)) {
    for (const entry of payload.headers) {
      if (Array.isArray(entry) && entry.length >= 2) {
        headers.append(String(entry[0]), String(entry[1]));
      }
    }
  }

  let body = null;
  if (typeof payload.bodyBase64 === 'string' && payload.bodyBase64.length > 0) {
    body = base64ToBytes(payload.bodyBase64);
  }

  return new Response(body, { status, headers });
}

async function runBridgeHandler(handler, request, context = {}) {
  const payload = JSON.stringify({
    request: await serializeRequest(request),
    runtime: normalizeRuntimeContext(context),
    context: {},
  });
  const result = await new Promise((resolve, reject) => {
    try {
      handler(payload, resolve, reject);
    } catch (error) {
      reject(error);
    }
  });
  return responseFromBridgePayload(result);
}

async function handle(request, context = {}) {
  const handler = globalThis.__osrv_main__;
  if (typeof handler !== 'function') {
    throw new Error(
      'globalThis.__osrv_main__ is not set. Ensure your Dart entry calls server.serve() and rebuild with `dart run osrv build`.',
    );
  }

  if (isBridgeHandler(handler)) {
    return runBridgeHandler(handler, request, context);
  }
  return await handler(request, context);
}

function serveWithMain(options) {
  const port = Number(options.port ?? process.env.PORT ?? 3000);
  const hostname = String(options.hostname ?? process.env.HOSTNAME ?? '0.0.0.0');
  return Bun.serve({
    port,
    hostname,
    development: false,
    reusePort: Boolean(options.reusePort ?? false),
    fetch(request, server) {
      let protocol = 'http';
      try {
        protocol = new URL(request.url).protocol.replace(':', '') || 'http';
      } catch (_) {}
      return handle(request, {
        provider: 'bun',
        runtime: 'bun',
        protocol,
        httpVersion: '1.1',
        tls: protocol === 'https',
        env: {},
        raw: { server },
      });
    },
  });
}

export async function serve(options = {}) {
  const handler = await waitForMain();
  if (typeof handler !== 'function') {
    throw new Error(
      'globalThis.__osrv_main__ is not set. Build output expects Dart JS core to register handler. Check dist/js/core/$coreJsName.',
    );
  }
  return serveWithMain(options);
}

if (import.meta.main) {
  await serve();
}
''');

  File('$outDir/js/deno/index.mjs').writeAsStringSync('''
if (typeof globalThis.self === 'undefined') {
  globalThis.self = globalThis;
}
await import('../core/$coreJsName');

const BODY_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);
const BRIDGE_MODE = 'json-v1';

function bytesToBase64(bytes) {
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

function base64ToBytes(base64) {
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

function formatAddr(addr) {
  if (!addr || typeof addr !== 'object') return null;
  if (typeof addr.hostname === 'string' && typeof addr.port === 'number') {
    return String(addr.hostname) + ':' + String(addr.port);
  }
  return null;
}

function normalizeRuntimeContext(input = {}) {
  const value = input && typeof input === 'object' ? input : {};
  const env =
    value.env && typeof value.env === 'object' && value.env !== null
      ? value.env
      : {};
  const protocol = typeof value.protocol === 'string' ? value.protocol : 'http';
  return {
    provider: typeof value.provider === 'string' ? value.provider : 'deno',
    runtime: typeof value.runtime === 'string' ? value.runtime : 'deno',
    protocol,
    httpVersion:
      typeof value.httpVersion === 'string' ? value.httpVersion : '1.1',
    localAddress:
      typeof value.localAddress === 'string' ? value.localAddress : null,
    remoteAddress:
      typeof value.remoteAddress === 'string' ? value.remoteAddress : null,
    ip: typeof value.ip === 'string' ? value.ip : null,
    tls: Boolean(value.tls ?? protocol === 'https'),
    env,
  };
}

async function serializeRequest(request) {
  const headers = [];
  for (const [name, value] of request.headers.entries()) {
    headers.push([name, value]);
  }

  const method = (request.method || 'GET').toUpperCase();
  let bodyBase64 = null;
  if (BODY_METHODS.has(method)) {
    const clone = request.clone();
    const buffer = await clone.arrayBuffer();
    if (buffer.byteLength > 0) {
      bodyBase64 = bytesToBase64(new Uint8Array(buffer));
    }
  }

  return {
    url: request.url,
    method,
    headers,
    bodyBase64,
  };
}

async function waitForMain(timeoutMs = 5000) {
  const startedAt = Date.now();
  while (Date.now() - startedAt <= timeoutMs) {
    const handler = globalThis.__osrv_main__;
    if (typeof handler === 'function') {
      return handler;
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  return null;
}

function isBridgeHandler(handler) {
  return (
    typeof handler === 'function' &&
    handler.__osrv_bridge__ === BRIDGE_MODE
  );
}

function responseFromBridgePayload(responsePayload) {
  const payload =
    typeof responsePayload === 'string'
      ? JSON.parse(responsePayload)
      : responsePayload;
  if (!payload || typeof payload !== 'object') {
    throw new Error('Invalid bridge response payload.');
  }

  const status = Number(payload.status ?? 500);
  const headers = new Headers();
  if (Array.isArray(payload.headers)) {
    for (const entry of payload.headers) {
      if (Array.isArray(entry) && entry.length >= 2) {
        headers.append(String(entry[0]), String(entry[1]));
      }
    }
  }

  let body = null;
  if (typeof payload.bodyBase64 === 'string' && payload.bodyBase64.length > 0) {
    body = base64ToBytes(payload.bodyBase64);
  }

  return new Response(body, { status, headers });
}

async function runBridgeHandler(handler, request, context = {}) {
  const payload = JSON.stringify({
    request: await serializeRequest(request),
    runtime: normalizeRuntimeContext(context),
    context: {},
  });
  const result = await new Promise((resolve, reject) => {
    try {
      handler(payload, resolve, reject);
    } catch (error) {
      reject(error);
    }
  });
  return responseFromBridgePayload(result);
}

async function handle(request, context = {}) {
  const handler = globalThis.__osrv_main__;
  if (typeof handler !== 'function') {
    throw new Error(
      'globalThis.__osrv_main__ is not set. Ensure your Dart entry calls server.serve() and rebuild with `dart run osrv build`.',
    );
  }

  if (isBridgeHandler(handler)) {
    return runBridgeHandler(handler, request, context);
  }
  return await handler(request, context);
}

function serveWithMain(options) {
  const port = Number(options.port ?? Deno.env.get('PORT') ?? 3000);
  const hostname = String(options.hostname ?? Deno.env.get('HOSTNAME') ?? '0.0.0.0');
  return Deno.serve({ port, hostname }, (request, info) => {
    let protocol = 'http';
    try {
      protocol = new URL(request.url).protocol.replace(':', '') || 'http';
    } catch (_) {}
    return handle(request, {
      provider: 'deno',
      runtime: 'deno',
      protocol,
      httpVersion: '1.1',
      localAddress: formatAddr(info?.localAddr),
      remoteAddress: formatAddr(info?.remoteAddr),
      ip: info?.remoteAddr?.hostname ?? null,
      tls: protocol === 'https',
      env: {},
      raw: { info },
    });
  });
}

export async function serve(options = {}) {
  const handler = await waitForMain();
  if (typeof handler !== 'function') {
    throw new Error(
      'globalThis.__osrv_main__ is not set. Build output expects Dart JS core to register handler. Check dist/js/core/$coreJsName.',
    );
  }
  return serveWithMain(options);
}

if (import.meta.main) {
  await serve();
}
''');

  File('$outDir/edge/cloudflare/index.mjs').writeAsStringSync('''
if (typeof globalThis.self === 'undefined') {
  globalThis.self = globalThis;
}
await import('../../js/core/$coreJsName');

const BODY_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);
const BRIDGE_MODE = 'json-v1';

function bytesToBase64(bytes) {
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

function base64ToBytes(base64) {
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

async function waitForMain(timeoutMs = 5000) {
  const startedAt = Date.now();
  while (Date.now() - startedAt <= timeoutMs) {
    const handler = globalThis.__osrv_main__;
    if (typeof handler === 'function') {
      return handler;
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  return null;
}

function isBridgeHandler(handler) {
  return (
    typeof handler === 'function' &&
    handler.__osrv_bridge__ === BRIDGE_MODE
  );
}

function normalizeEnv(env) {
  if (env && typeof env === 'object') {
    return env;
  }
  return {};
}

function normalizeRuntimeContext(input = {}) {
  const value = input && typeof input === 'object' ? input : {};
  const protocol = typeof value.protocol === 'string' ? value.protocol : 'http';
  return {
    provider:
      typeof value.provider === 'string' ? value.provider : 'cloudflare',
    runtime: typeof value.runtime === 'string' ? value.runtime : 'cloudflare',
    protocol,
    httpVersion:
      typeof value.httpVersion === 'string' ? value.httpVersion : '1.1',
    localAddress:
      typeof value.localAddress === 'string' ? value.localAddress : null,
    remoteAddress:
      typeof value.remoteAddress === 'string' ? value.remoteAddress : null,
    ip: typeof value.ip === 'string' ? value.ip : null,
    tls: Boolean(value.tls ?? protocol === 'https'),
    env: normalizeEnv(value.env),
  };
}

async function serializeRequest(request) {
  const headers = [];
  for (const [name, value] of request.headers.entries()) {
    headers.push([name, value]);
  }

  const method = (request.method || 'GET').toUpperCase();
  let bodyBase64 = null;
  if (BODY_METHODS.has(method)) {
    const clone = request.clone();
    const buffer = await clone.arrayBuffer();
    if (buffer.byteLength > 0) {
      bodyBase64 = bytesToBase64(new Uint8Array(buffer));
    }
  }

  return {
    url: request.url,
    method,
    headers,
    bodyBase64,
  };
}

function responseFromBridgePayload(responsePayload) {
  const payload =
    typeof responsePayload === 'string'
      ? JSON.parse(responsePayload)
      : responsePayload;
  if (!payload || typeof payload !== 'object') {
    throw new Error('Invalid bridge response payload.');
  }

  const status = Number(payload.status ?? 500);
  const headers = new Headers();
  if (Array.isArray(payload.headers)) {
    for (const entry of payload.headers) {
      if (Array.isArray(entry) && entry.length >= 2) {
        headers.append(String(entry[0]), String(entry[1]));
      }
    }
  }

  let body = null;
  if (typeof payload.bodyBase64 === 'string' && payload.bodyBase64.length > 0) {
    body = base64ToBytes(payload.bodyBase64);
  }

  return new Response(body, { status, headers });
}

async function runBridgeHandler(handler, request, context = {}) {
  const payload = JSON.stringify({
    request: await serializeRequest(request),
    runtime: normalizeRuntimeContext(context),
    context: {},
  });
  const result = await new Promise((resolve, reject) => {
    try {
      handler(payload, resolve, reject);
    } catch (error) {
      reject(error);
    }
  });
  return responseFromBridgePayload(result);
}

async function handle(request, context = {}) {
  const handler = await waitForMain();
  if (typeof handler !== 'function') {
    return new Response('globalThis.__osrv_main__ is not set.', { status: 500 });
  }
  if (isBridgeHandler(handler)) {
    return runBridgeHandler(handler, request, context);
  }
  return handler(request, context);
}

export default {
  async fetch(request, env, ctx) {
    let protocol = 'http';
    try {
      protocol = new URL(request.url).protocol.replace(':', '') || 'http';
    } catch (_) {}
    const ip = request.headers.get('cf-connecting-ip');
    return handle(request, {
      provider: 'cloudflare',
      runtime: 'cloudflare',
      protocol,
      httpVersion: '1.1',
      tls: protocol === 'https',
      ip: ip || null,
      env: normalizeEnv(env),
      waitUntil: (promise) => ctx?.waitUntil?.(promise),
      ctx,
      raw: { env, ctx },
    });
  },
};
''');

  File('$outDir/edge/vercel/index.mjs').writeAsStringSync('''
if (typeof globalThis.self === 'undefined') {
  globalThis.self = globalThis;
}
await import('../../js/core/$coreJsName');

const BODY_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);
const BRIDGE_MODE = 'json-v1';

function bytesToBase64(bytes) {
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

function base64ToBytes(base64) {
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

async function waitForMain(timeoutMs = 5000) {
  const startedAt = Date.now();
  while (Date.now() - startedAt <= timeoutMs) {
    const handler = globalThis.__osrv_main__;
    if (typeof handler === 'function') {
      return handler;
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  return null;
}

function isBridgeHandler(handler) {
  return (
    typeof handler === 'function' &&
    handler.__osrv_bridge__ === BRIDGE_MODE
  );
}

function normalizeEnv(context) {
  if (context?.env && typeof context.env === 'object') {
    return context.env;
  }
  return {};
}

function normalizeRuntimeContext(input = {}) {
  const value = input && typeof input === 'object' ? input : {};
  const protocol = typeof value.protocol === 'string' ? value.protocol : 'http';
  return {
    provider: typeof value.provider === 'string' ? value.provider : 'vercel',
    runtime: typeof value.runtime === 'string' ? value.runtime : 'vercel',
    protocol,
    httpVersion:
      typeof value.httpVersion === 'string' ? value.httpVersion : '1.1',
    localAddress:
      typeof value.localAddress === 'string' ? value.localAddress : null,
    remoteAddress:
      typeof value.remoteAddress === 'string' ? value.remoteAddress : null,
    ip: typeof value.ip === 'string' ? value.ip : null,
    tls: Boolean(value.tls ?? protocol === 'https'),
    env: normalizeEnv(value),
  };
}

async function serializeRequest(request) {
  const headers = [];
  for (const [name, value] of request.headers.entries()) {
    headers.push([name, value]);
  }

  const method = (request.method || 'GET').toUpperCase();
  let bodyBase64 = null;
  if (BODY_METHODS.has(method)) {
    const clone = request.clone();
    const buffer = await clone.arrayBuffer();
    if (buffer.byteLength > 0) {
      bodyBase64 = bytesToBase64(new Uint8Array(buffer));
    }
  }

  return {
    url: request.url,
    method,
    headers,
    bodyBase64,
  };
}

function responseFromBridgePayload(responsePayload) {
  const payload =
    typeof responsePayload === 'string'
      ? JSON.parse(responsePayload)
      : responsePayload;
  if (!payload || typeof payload !== 'object') {
    throw new Error('Invalid bridge response payload.');
  }

  const status = Number(payload.status ?? 500);
  const headers = new Headers();
  if (Array.isArray(payload.headers)) {
    for (const entry of payload.headers) {
      if (Array.isArray(entry) && entry.length >= 2) {
        headers.append(String(entry[0]), String(entry[1]));
      }
    }
  }

  let body = null;
  if (typeof payload.bodyBase64 === 'string' && payload.bodyBase64.length > 0) {
    body = base64ToBytes(payload.bodyBase64);
  }

  return new Response(body, { status, headers });
}

async function runBridgeHandler(handler, request, context = {}) {
  const payload = JSON.stringify({
    request: await serializeRequest(request),
    runtime: normalizeRuntimeContext(context),
    context: {},
  });
  const result = await new Promise((resolve, reject) => {
    try {
      handler(payload, resolve, reject);
    } catch (error) {
      reject(error);
    }
  });
  return responseFromBridgePayload(result);
}

export default async function handler(request, context) {
  const main = await waitForMain();
  if (typeof main !== 'function') {
    return new Response('globalThis.__osrv_main__ is not set.', { status: 500 });
  }

  let protocol = 'http';
  try {
    protocol = new URL(request.url).protocol.replace(':', '') || 'http';
  } catch (_) {}
  const normalized = {
    provider: 'vercel',
    runtime: 'vercel',
    protocol,
    httpVersion: '1.1',
    tls: protocol === 'https',
    env: normalizeEnv(context),
    waitUntil: (promise) => context?.waitUntil?.(promise),
    ctx: context,
    raw: { context },
  };
  if (isBridgeHandler(main)) {
    return runBridgeHandler(main, request, normalized);
  }
  return main(request, normalized);
}
''');

  File('$outDir/edge/netlify/index.mjs').writeAsStringSync('''
if (typeof globalThis.self === 'undefined') {
  globalThis.self = globalThis;
}
await import('../../js/core/$coreJsName');

const BODY_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);
const BRIDGE_MODE = 'json-v1';

function bytesToBase64(bytes) {
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

function base64ToBytes(base64) {
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

async function waitForMain(timeoutMs = 5000) {
  const startedAt = Date.now();
  while (Date.now() - startedAt <= timeoutMs) {
    const handler = globalThis.__osrv_main__;
    if (typeof handler === 'function') {
      return handler;
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  return null;
}

function isBridgeHandler(handler) {
  return (
    typeof handler === 'function' &&
    handler.__osrv_bridge__ === BRIDGE_MODE
  );
}

function normalizeEnv(context) {
  if (context?.env && typeof context.env === 'object') {
    return context.env;
  }
  return {};
}

function normalizeRuntimeContext(input = {}) {
  const value = input && typeof input === 'object' ? input : {};
  const protocol = typeof value.protocol === 'string' ? value.protocol : 'http';
  return {
    provider: typeof value.provider === 'string' ? value.provider : 'netlify',
    runtime: typeof value.runtime === 'string' ? value.runtime : 'netlify',
    protocol,
    httpVersion:
      typeof value.httpVersion === 'string' ? value.httpVersion : '1.1',
    localAddress:
      typeof value.localAddress === 'string' ? value.localAddress : null,
    remoteAddress:
      typeof value.remoteAddress === 'string' ? value.remoteAddress : null,
    ip: typeof value.ip === 'string' ? value.ip : null,
    tls: Boolean(value.tls ?? protocol === 'https'),
    env: normalizeEnv(value),
  };
}

async function serializeRequest(request) {
  const headers = [];
  for (const [name, value] of request.headers.entries()) {
    headers.push([name, value]);
  }

  const method = (request.method || 'GET').toUpperCase();
  let bodyBase64 = null;
  if (BODY_METHODS.has(method)) {
    const clone = request.clone();
    const buffer = await clone.arrayBuffer();
    if (buffer.byteLength > 0) {
      bodyBase64 = bytesToBase64(new Uint8Array(buffer));
    }
  }

  return {
    url: request.url,
    method,
    headers,
    bodyBase64,
  };
}

function responseFromBridgePayload(responsePayload) {
  const payload =
    typeof responsePayload === 'string'
      ? JSON.parse(responsePayload)
      : responsePayload;
  if (!payload || typeof payload !== 'object') {
    throw new Error('Invalid bridge response payload.');
  }

  const status = Number(payload.status ?? 500);
  const headers = new Headers();
  if (Array.isArray(payload.headers)) {
    for (const entry of payload.headers) {
      if (Array.isArray(entry) && entry.length >= 2) {
        headers.append(String(entry[0]), String(entry[1]));
      }
    }
  }

  let body = null;
  if (typeof payload.bodyBase64 === 'string' && payload.bodyBase64.length > 0) {
    body = base64ToBytes(payload.bodyBase64);
  }

  return new Response(body, { status, headers });
}

async function runBridgeHandler(handler, request, context = {}) {
  const payload = JSON.stringify({
    request: await serializeRequest(request),
    runtime: normalizeRuntimeContext(context),
    context: {},
  });
  const result = await new Promise((resolve, reject) => {
    try {
      handler(payload, resolve, reject);
    } catch (error) {
      reject(error);
    }
  });
  return responseFromBridgePayload(result);
}

export default async (request, context) => {
  const main = await waitForMain();
  if (typeof main !== 'function') {
    return new Response('globalThis.__osrv_main__ is not set.', { status: 500 });
  }

  let protocol = 'http';
  try {
    protocol = new URL(request.url).protocol.replace(':', '') || 'http';
  } catch (_) {}
  const normalized = {
    provider: 'netlify',
    runtime: 'netlify',
    protocol,
    httpVersion: '1.1',
    tls: protocol === 'https',
    env: normalizeEnv(context),
    waitUntil: (promise) => context?.waitUntil?.(promise),
    ctx: context,
    raw: { context },
  };
  if (isBridgeHandler(main)) {
    return runBridgeHandler(main, request, normalized);
  }
  return main(request, normalized);
};
''');
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  required bool silent,
}) async {
  if (!silent) {
    stdout.writeln('\$ $executable ${arguments.join(' ')}');
  }

  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
  );

  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(executable, arguments, 'Command failed', code);
  }
}

Future<_ConfigFile> _loadConfigFile(String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    return const _ConfigFile();
  }

  final configMap = await _evaluateConfigMap(file);
  if (configMap == null) {
    return const _ConfigFile();
  }

  String? readString(String key) {
    final value = configMap[key];
    if (value == null) {
      return null;
    }
    return value.toString();
  }

  return _ConfigFile(
    port: readString('port'),
    hostname: readString('hostname'),
    protocol: readString('protocol'),
  );
}

Future<Map<String, Object?>?> _evaluateConfigMap(File file) async {
  final tempDir = await Directory.systemTemp.createTemp('osrv-config-');
  final runner = File('${tempDir.path}/runner.dart');
  try {
    final configUri = file.absolute.uri.toString();
    runner.writeAsStringSync('''
import 'dart:convert';
import 'dart:io';

import '$configUri';

void main() {
  final dynamic value = osrvConfig;
  if (value is! Map) {
    stderr.writeln('`osrvConfig` must be a Map.');
    exit(2);
  }

  stdout.write(jsonEncode(Map<String, Object?>.from(value)));
}
''');

    final result = await Process.run('dart', <String>[
      'run',
      runner.path,
    ], workingDirectory: file.parent.path);

    if (result.exitCode != 0) {
      stderr.writeln('[osrv] failed to execute config `${file.path}`.');
      if (result.stderr != null && result.stderr.toString().trim().isNotEmpty) {
        stderr.writeln(result.stderr.toString().trim());
      }
      return null;
    }

    final text = result.stdout?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      return null;
    }

    return Map<String, Object?>.from(decoded);
  } finally {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}

String? _resolveEntry(String preferred) {
  final preferredFile = File(preferred);
  if (preferredFile.existsSync()) {
    return preferred;
  }

  if (preferred == _defaultEntry) {
    final fallback = File('bin/server.dart');
    if (fallback.existsSync()) {
      return 'bin/server.dart';
    }
  }

  return null;
}

void _ensureDir(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
}

String _basenameWithoutExtension(String path) {
  final normalized = path.replaceAll('\\', '/');
  final fileName = normalized.split('/').last;
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex <= 0) {
    return fileName;
  }

  return fileName.substring(0, dotIndex);
}

String? _firstNonEmpty(String? first, String? second, [String? third]) {
  for (final value in <String?>[first, second, third]) {
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  return null;
}

final class _ConfigFile {
  const _ConfigFile({this.port, this.hostname, this.protocol});

  final String? port;
  final String? hostname;
  final String? protocol;
}
