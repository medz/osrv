#!/usr/bin/env sh
set -eu

exec deno run --allow-net build/server.js
