import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import { spawn, type ChildProcess } from 'node:child_process';
import { rmSync } from 'node:fs';
import { createServer } from 'node:net';
import { resolve } from 'node:path';

const repoRoot = resolve(import.meta.dir, '..', '..', '..');
const distDir = resolve(repoRoot, '.tmp_js_runtime_tests');

const nodeEntry = resolve(distDir, 'js', 'node', 'index.mjs');
const bunEntry = resolve(distDir, 'js', 'bun', 'index.mjs');
const denoEntry = resolve(distDir, 'js', 'deno', 'index.mjs');
const runtimeLogs = new WeakMap<ChildProcess, { stdout: string; stderr: string }>();
const runtimeSpawnErrors = new WeakMap<ChildProcess, string>();

beforeAll(async () => {
  await runCommand('dart', [
    'run',
    'bin/osrv.dart',
    'build',
    '--entry=example/server.dart',
    `--out-dir=${distDir}`,
    '--silent',
  ]);
});

afterAll(() => {
  rmSync(distDir, { recursive: true, force: true });
});

describe('runtime integrations', () => {
  test(
      'node runtime serves http and rejects websocket upgrade',
    async () => {
      const port = await getFreePort();
      const baseUrl = `http://127.0.0.1:${port}`;
      const baseWsUrl = `ws://127.0.0.1:${port}`;
      const child = startRuntime('node', [nodeEntry], {
        HOST: '127.0.0.1',
        PORT: String(port),
      });
      try {
        runtimeUnderCheck = child;
        await waitForServer(`${baseUrl}/`);
        runtimeUnderCheck = null;

        const res = await fetchWithTimeout(`${baseUrl}/`, 1500);
        expect(res.status).toBe(200);
        const body = (await res.json()) as { ok: boolean; path: string };
        expect(body.ok).toBe(true);
        expect(body.path).toBe('/');

        await expectWebSocketFailure(`${baseWsUrl}/ws`);
      } finally {
        runtimeUnderCheck = null;
        await stopRuntime(child);
      }
    },
    20000,
  );

  test(
      'bun runtime serves http and websocket echo',
    async () => {
      const port = await getFreePort();
      const baseUrl = `http://127.0.0.1:${port}`;
      const baseWsUrl = `ws://127.0.0.1:${port}`;
      const child = startRuntime('bun', [bunEntry], {
        HOST: '127.0.0.1',
        PORT: String(port),
      });
      try {
        runtimeUnderCheck = child;
        await waitForServer(`${baseUrl}/`);
        runtimeUnderCheck = null;

        const res = await fetchWithTimeout(`${baseUrl}/`, 1500);
        expect(res.status).toBe(200);
        const body = (await res.json()) as { ok: boolean; path: string };
        expect(body.ok).toBe(true);
        expect(body.path).toBe('/');

        const echoed = await webSocketEcho(`${baseWsUrl}/ws`, 'from-js-test');
        expect(echoed).toBe('echo:from-js-test');
      } finally {
        runtimeUnderCheck = null;
        await stopRuntime(child);
      }
    },
    20000,
  );

  test(
    'deno runtime serves http and websocket echo (if installed)',
    async () => {
      const hasDeno = await commandExists('deno');
      if (!hasDeno) {
        return;
      }

      const port = await getFreePort();
      const baseUrl = `http://127.0.0.1:${port}`;
      const baseWsUrl = `ws://127.0.0.1:${port}`;
      const child = startRuntime(
        'deno',
        ['run', '--allow-net', '--allow-env', '--allow-read', denoEntry],
        {
          HOST: '127.0.0.1',
          PORT: String(port),
        },
      );
      try {
        runtimeUnderCheck = child;
        await waitForServer(`${baseUrl}/`);
        runtimeUnderCheck = null;

        const res = await fetchWithTimeout(`${baseUrl}/`, 1500);
        expect(res.status).toBe(200);
        const body = (await res.json()) as { ok: boolean; path: string };
        expect(body.ok).toBe(true);
        expect(body.path).toBe('/');

        const echoed = await webSocketEcho(`${baseWsUrl}/ws`, 'from-deno-test');
        expect(echoed).toBe('echo:from-deno-test');
      } finally {
        runtimeUnderCheck = null;
        await stopRuntime(child);
      }
    },
    20000,
  );
});

function startRuntime(
  command: string,
  args: string[],
  env: Record<string, string> = {},
): ChildProcess {
  const child = spawn(command, args, {
    cwd: repoRoot,
    env: { ...process.env, ...env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  const logs = { stdout: '', stderr: '' };
  runtimeLogs.set(child, logs);

  child.stdout?.setEncoding('utf8');
  child.stderr?.setEncoding('utf8');
  child.stdout?.on('data', (chunk: string) => {
    logs.stdout += chunk;
  });
  child.stderr?.on('data', (chunk: string) => {
    logs.stderr += chunk;
  });
  child.once('error', (error) => {
    runtimeSpawnErrors.set(child, `${error.name}: ${error.message}`);
  });

  return child;
}

async function stopRuntime(child: ChildProcess): Promise<void> {
  if (child.exitCode !== null) {
    return;
  }

  child.kill('SIGTERM');
  await waitForChildExit(child, 2000);

  if (child.exitCode === null) {
    child.kill('SIGKILL');
    await waitForChildExit(child, 2000);
  }
}

async function waitForServer(url: string, timeoutMs = 6000): Promise<void> {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    if (currentRuntimeExitInfo() !== null) {
      throw new Error(currentRuntimeExitInfo()!);
    }

    try {
      const res = await fetchWithTimeout(url, 800);
      if (res.status > 0) {
        return;
      }
    } catch {
      // Retry while server boots.
    }

    await sleep(120);
  }

  const child = runtimeUnderCheck;
  const logs = child == null ? null : runtimeLogs.get(child);
  throw new Error(
    [
      `Timed out waiting for runtime server: ${url}`,
      child == null
          ? ''
          : `pid=${child.pid ?? 'unknown'}, running=${child.exitCode === null}`,
      logs?.stdout.trim() ?? '',
      logs?.stderr.trim() ?? '',
    ]
      .filter((line) => line.length > 0)
      .join('\n'),
  );
}

async function fetchWithTimeout(url: string, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

let runtimeUnderCheck: ChildProcess | null = null;

function currentRuntimeExitInfo(): string | null {
  const child = runtimeUnderCheck;
  if (child == null) {
    return null;
  }

  const spawnError = runtimeSpawnErrors.get(child);
  if (spawnError != null) {
    const logs = runtimeLogs.get(child);
    return [
      `Runtime failed to spawn: ${spawnError}`,
      logs?.stdout.trim() ?? '',
      logs?.stderr.trim() ?? '',
    ]
      .filter((line) => line.length > 0)
      .join('\n');
  }

  if (child.exitCode === null) {
    return null;
  }

  const logs = runtimeLogs.get(child);
  return [
    `Runtime exited early with code ${child.exitCode}.`,
    logs?.stdout.trim() ?? '',
    logs?.stderr.trim() ?? '',
  ]
    .filter((line) => line.length > 0)
    .join('\n');
}

async function webSocketEcho(url: string, message: string): Promise<string> {
  const ws = new WebSocket(url);

  return await new Promise<string>((resolve, reject) => {
    const timeout = setTimeout(() => {
      ws.close();
      reject(new Error(`WebSocket echo timeout: ${url}`));
    }, 4000);

    ws.addEventListener('open', () => {
      ws.send(message);
    });

    ws.addEventListener('message', (event: MessageEvent) => {
      clearTimeout(timeout);
      ws.close();
      resolve(String(event.data));
    });

    ws.addEventListener('error', () => {
      clearTimeout(timeout);
      reject(new Error(`WebSocket error: ${url}`));
    });
  });
}

async function expectWebSocketFailure(url: string): Promise<void> {
  const ws = new WebSocket(url);

  await new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(() => {
      ws.close();
      reject(new Error(`Expected websocket failure but timed out: ${url}`));
    }, 2500);

    ws.addEventListener('open', () => {
      clearTimeout(timeout);
      ws.close();
      reject(new Error(`Expected websocket failure but connected: ${url}`));
    });

    ws.addEventListener('close', () => {
      clearTimeout(timeout);
      resolve();
    });

    ws.addEventListener('error', () => {
      clearTimeout(timeout);
      resolve();
    });
  });
}

async function commandExists(command: string): Promise<boolean> {
  try {
    await runCommand(command, ['--version']);
    return true;
  } catch {
    return false;
  }
}

async function runCommand(command: string, args: string[]): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: repoRoot,
      env: process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let stdout = '';
    let stderr = '';

    child.stdout?.setEncoding('utf8');
    child.stderr?.setEncoding('utf8');

    child.stdout?.on('data', (chunk: string) => {
      stdout += chunk;
    });
    child.stderr?.on('data', (chunk: string) => {
      stderr += chunk;
    });

    child.once('error', reject);
    child.once('exit', (code) => {
      if (code === 0) {
        resolve();
        return;
      }

      reject(
        new Error(
          [
            `Command failed: ${command} ${args.join(' ')}`,
            stdout.trim(),
            stderr.trim(),
          ]
            .filter((line) => line.length > 0)
            .join('\n'),
        ),
      );
    });
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForChildExit(child: ChildProcess, timeoutMs: number): Promise<void> {
  if (child.exitCode !== null) {
    return;
  }

  await Promise.race([
    new Promise<void>((resolve) => {
      const onDone = () => {
        child.off('exit', onDone);
        child.off('close', onDone);
        resolve();
      };

      child.on('exit', onDone);
      child.on('close', onDone);
      if (child.exitCode !== null) {
        onDone();
      }
    }),
    sleep(timeoutMs),
  ]);
}

async function getFreePort(): Promise<number> {
  return await new Promise<number>((resolve, reject) => {
    const server = createServer();

    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      if (address == null || typeof address === 'string') {
        server.close(() => {
          reject(new Error('Failed to resolve free TCP port.'));
        });
        return;
      }

      const port = address.port;
      server.close((error) => {
        if (error != null) {
          reject(error);
          return;
        }
        resolve(port);
      });
    });
  });
}
