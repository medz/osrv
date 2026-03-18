#!/usr/bin/env sh
set -eu

mkdir -p build
npm ci --no-fund --no-audit
dart compile js worker.dart -o build/worker.dart.js
