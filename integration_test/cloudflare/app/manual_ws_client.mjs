const [url, protocol = 'chat'] = process.argv.slice(2);

if (!url) {
  console.error('usage: node ./manual_ws_client.mjs <ws-url> [protocol]');
  process.exit(64);
}

const socket = protocol ? new WebSocket(url, protocol) : new WebSocket(url);
let sawConnected = false;
let sawEcho = false;
let settled = false;

const timer = setTimeout(() => {
  fail('websocket client timed out waiting for a clean close');
}, 5000);

socket.addEventListener('open', () => {
  socket.send('ping');
});

socket.addEventListener('message', (event) => {
  if (event.data === 'connected') {
    sawConnected = true;
    return;
  }

  if (event.data === 'echo:ping') {
    sawEcho = true;
    socket.close(1000, 'client done');
  }
});

socket.addEventListener('error', () => {
  fail('websocket client observed an error event');
});

socket.addEventListener('close', (event) => {
  clearTimeout(timer);
  if (settled) {
    return;
  }

  if (!sawConnected || !sawEcho) {
    fail(
      `websocket closed before completing echo flow (connected=${sawConnected}, echo=${sawEcho})`,
    );
    return;
  }

  if (event.code !== 1000) {
    fail(`expected close code 1000, got ${event.code}`);
    return;
  }

  settled = true;
  console.log(`CLOSE:${event.code}:${event.reason}`);
  process.exit(0);
});

function fail(message) {
  clearTimeout(timer);
  if (settled) {
    return;
  }

  settled = true;
  console.error(message);
  process.exit(1);
}
