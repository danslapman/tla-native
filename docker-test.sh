#!/usr/bin/env bash
# docker-test.sh - Run the Linux TLC test suite inside Docker (for macOS hosts)
#
# Usage:
#   ./docker-test.sh                       # run all models with runtime ≤60s
#   MAX_RUNTIME=30 ./docker-test.sh        # only run fast models
#   VERBOSE=1 ./docker-test.sh             # show full TLC output for each model
#   MODEL_TIMEOUT=60 ./docker-test.sh      # per-model hard timeout (default: 120s)
#
# Requires:
#   - Docker with access to container-registry.oracle.com
#   - ./tlc-native (Linux binary built by docker-build.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="container-registry.oracle.com/graalvm/native-image:24"
MAX_RUNTIME="${MAX_RUNTIME:-60}"
MODEL_TIMEOUT="${MODEL_TIMEOUT:-120}"
VERBOSE="${VERBOSE:-0}"

if ! command -v docker &>/dev/null; then
  echo "ERROR: docker not found in PATH" >&2
  exit 1
fi

if [[ ! -f "${SCRIPT_DIR}/tlc-native" || ! -x "${SCRIPT_DIR}/tlc" ]]; then
  echo "ERROR: Linux build artifacts not found (tlc-native / tlc)." >&2
  echo "       Run './docker-build.sh' first to build the Linux binary." >&2
  exit 1
fi

echo "==> Docker test: ${IMAGE}"
echo "    Max runtime:    ${MAX_RUNTIME}s"
echo "    Model timeout:  ${MODEL_TIMEOUT}s"
echo "    Mount:          ${SCRIPT_DIR} -> /work"
echo ""

docker run --rm \
  --entrypoint bash \
  -v "${SCRIPT_DIR}:/work" \
  -w /work \
  -e MAX_RUNTIME="${MAX_RUNTIME}" \
  -e MODEL_TIMEOUT="${MODEL_TIMEOUT}" \
  -e VERBOSE="${VERBOSE}" \
  "${IMAGE}" \
  -c "microdnf install -y jq git >/dev/null && ./test-linux.sh"
