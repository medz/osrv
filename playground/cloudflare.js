import './cloudflare.dart.js';

const worker = globalThis.__osrvCloudflareWorker;

if (!worker) {
  throw new Error(
    'Missing globalThis.__osrvCloudflareWorker. Compile playground/cloudflare.dart to playground/cloudflare.dart.js first.',
  );
}

export default worker;
