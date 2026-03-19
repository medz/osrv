#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
: "${HOST:=127.0.0.1}"
: "${PORT:=8787}"

cd "$script_dir"

stdout_log=$(mktemp)
stderr_log=$(mktemp)
pid=''

cleanup() {
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" || true
  fi
  rm -f "$stdout_log" "$stderr_log"
}

trap cleanup EXIT INT TERM

./build.sh
HOST="$HOST" PORT="$PORT" ./run.sh >"$stdout_log" 2>"$stderr_log" &
pid=$!

ready=0
for _ in $(seq 1 50); do
  if curl -fsS "http://$HOST:$PORT/hello" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.2
done

if [ "$ready" -ne 1 ]; then
  echo "wrangler app did not become ready" >&2
  cat "$stdout_log" >&2 || true
  cat "$stderr_log" >&2 || true
  exit 1
fi

curl -fsS "http://$HOST:$PORT/hello"
echo
node ./manual_ws_client.mjs "ws://$HOST:$PORT/chat" chat

if [ -s "$stderr_log" ]; then
  echo "wrangler stderr (diagnostic):" >&2
  cat "$stderr_log" >&2
fi
