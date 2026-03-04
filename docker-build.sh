#!/usr/bin/env bash
# docker-build.sh - Build the Linux TLC native image inside Docker (for macOS hosts)
#
# Usage:
#   ./docker-build.sh           # build native image
#   ./docker-build.sh --trace   # run TLC under native-image-agent to collect config
#   ./docker-build.sh --build   # same as default
#   BUILD_MEMORY=12g ./docker-build.sh  # customize build-time heap (default: 8g)
#
# Requires:
#   - Docker with access to container-registry.oracle.com
#   - tla2tools.jar in the same directory as this script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="container-registry.oracle.com/graalvm/native-image:24"
BUILD_MEMORY="${BUILD_MEMORY:-8g}"

# Determine mode to pass through to build-linux.sh
case "${1:-build}" in
  --trace)        MODE="--trace" ;;
  --build | build) MODE="--build" ;;
  *)
    echo "Usage: $0 [--trace|--build]" >&2
    echo "  --trace   run TLC under native-image-agent to collect reflection config" >&2
    echo "  --build   build the native image (default)" >&2
    exit 1
    ;;
esac

if ! command -v docker &>/dev/null; then
  echo "ERROR: docker not found in PATH" >&2
  exit 1
fi

echo "==> Docker build: ${IMAGE}"
echo "    Mode:   ${MODE}"
echo "    Heap:   ${BUILD_MEMORY}"
echo "    Mount:  ${SCRIPT_DIR} -> /work"
echo ""

docker run --rm \
  --entrypoint bash \
  -v "${SCRIPT_DIR}:/work" \
  -w /work \
  -e BUILD_MEMORY="${BUILD_MEMORY}" \
  "${IMAGE}" \
  -c "microdnf install -y unzip >/dev/null && ./build-linux.sh ${MODE}"
