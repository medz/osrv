const MAIN_READY_PROMISE_KEY = '__osrv_main_ready_promise__';
const MAIN_READY_RESOLVE_KEY = '__osrv_main_ready_resolve__';
const UPGRADE_RESPONSE_MARKER = '__osrv_upgrade_response__';

export function getMainHandler() {
  return globalThis.__osrv_main__;
}

function ensureMainReadyPromise() {
  const existing = globalThis[MAIN_READY_PROMISE_KEY];
  if (existing && typeof existing.then === 'function') {
    return existing;
  }

  const current = getMainHandler();
  if (typeof current === 'function') {
    const ready = Promise.resolve(current);
    globalThis[MAIN_READY_PROMISE_KEY] = ready;
    globalThis[MAIN_READY_RESOLVE_KEY] = null;
    return ready;
  }

  let resolveReady;
  const ready = new Promise((resolve) => {
    resolveReady = resolve;
  });
  globalThis[MAIN_READY_PROMISE_KEY] = ready;
  globalThis[MAIN_READY_RESOLVE_KEY] = (handler) => {
    resolveReady(handler);
    globalThis[MAIN_READY_RESOLVE_KEY] = null;
  };
  return ready;
}

const mainReadyPromise = ensureMainReadyPromise();

export async function waitForMain() {
  const handler = getMainHandler();
  if (typeof handler === 'function') {
    return handler;
  }
  return mainReadyPromise;
}

export function isUpgradeBridgeResponse(value) {
  return Boolean(
    value &&
      typeof value === 'object' &&
      value[UPGRADE_RESPONSE_MARKER] === true &&
      Number(value.status) === 101,
  );
}
