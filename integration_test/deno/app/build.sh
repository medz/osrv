#!/usr/bin/env sh
set -eu

mkdir -p build
dart compile js server.dart -o build/server.js
