import WebSocket from 'ws';

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

socket.on('open', () => {
  socket.send('ping');
});

socket.on('message', (data, isBinary) => {
  if (isBinary) {
    fail('websocket client received an unexpected binary frame');
    return;
  }

  const text = data.toString();
  if (text === 'connected') {
    sawConnected = true;
    return;
  }

  if (text === 'echo:ping') {
    sawEcho = true;
    socket.close(1000, 'client done');
    return;
  }

  fail(`websocket client received unexpected text frame: ${text}`);
});

socket.on('error', (error) => {
  fail(`websocket client observed an error event: ${error}`);
});

socket.on('close', (code, reasonBuffer) => {
  clearTimeout(timer);
  if (settled) {
    return;
  }

  const reason = reasonBuffer.toString();

  if (!sawConnected || !sawEcho) {
    fail(
      `websocket closed before completing echo flow (connected=${sawConnected}, echo=${sawEcho})`,
    );
    return;
  }

  if (code !== 1000) {
    fail(`expected close code 1000, got ${code}`);
    return;
  }

  settled = true;
  console.log(`CLOSE:${code}:${reason}`);
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
