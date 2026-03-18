#!/usr/bin/env sh
set -eu

: "${HOST:=127.0.0.1}"
: "${PORT:=8787}"

exec npm exec -- wrangler dev \
  --config wrangler.jsonc \
  --local \
  --ip "$HOST" \
  --port "$PORT" \
  --log-level error
