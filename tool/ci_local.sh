#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./tool/ci_local.sh [job]
  ./tool/ci_local.sh --job <job>
  ./tool/ci_local.sh --native

Options:
  --job <job>   Run a specific GitHub Actions job with act.
  --native      Run the CI-equivalent commands directly instead of act.
  --help        Show this help text.

Environment:
  OSRV_ACT_IMAGE  Override the Docker image used for ubuntu-latest.
                  Default: ghcr.io/catthehacker/ubuntu:act-latest
EOF
}

job=''
native='false'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --job)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Missing value for --job" >&2
        exit 1
      fi
      job="$1"
      ;;
    --native)
      native='true'
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$job" ]]; then
        job="$1"
      else
        echo "Unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
  shift
done

run_native() {
  echo "Running CI-equivalent commands locally"
  dart pub get
  dart format --output=none --set-exit-if-changed .
  dart analyze
  dart test test
  dart test -p vm \
    integration_test/dart \
    integration_test/compile \
    integration_test/node/runtime_process_test.dart \
    integration_test/bun/runtime_process_test.dart \
    integration_test/deno/runtime_process_test.dart \
    integration_test/cloudflare/runtime_process_test.dart
  dart test -p node \
    integration_test/bun/preflight_test.dart \
    integration_test/deno/preflight_test.dart \
    integration_test/node/host_runtime_test.dart \
    integration_test/cloudflare/worker_host_test.dart \
    integration_test/vercel/fetch_export_test.dart \
    integration_test/netlify/fetch_export_test.dart \
    integration_test/web/request_bridge_test.dart
}

if [[ "$native" == 'true' ]]; then
  run_native
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required to run GitHub Actions locally with act." >&2
  exit 1
fi

if ! command -v act >/dev/null 2>&1; then
  cat >&2 <<'EOF'
act is not installed.

Install it, then rerun:
  brew install act

Or use:
  ./tool/ci_local.sh --native
EOF
  exit 1
fi

image="${OSRV_ACT_IMAGE:-ghcr.io/catthehacker/ubuntu:act-latest}"

args=(
  pull_request
  --workflows
  .github/workflows/ci.yml
  -P
  "ubuntu-latest=${image}"
)

if [[ -n "$job" ]]; then
  args+=(--job "$job")
fi

echo "Running GitHub Actions locally with act"
echo "Image: ${image}"
if [[ -n "$job" ]]; then
  echo "Job: ${job}"
else
  echo "Job: all"
fi

exec act "${args[@]}"
