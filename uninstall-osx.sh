#!/usr/bin/env bash
# uninstall-osx.sh - Remove tlc installed by install-osx.sh

set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
STDLIB_DIR="${HOME}/Library/Application Support/tlc"

echo "==> Uninstalling tlc..."

removed=0

if [[ -f "${BIN_DIR}/tlc" ]]; then
  rm -f "${BIN_DIR}/tlc"
  echo "    Removed: ${BIN_DIR}/tlc"
  removed=1
fi

if [[ -f "${BIN_DIR}/tlc-native" ]]; then
  rm -f "${BIN_DIR}/tlc-native"
  echo "    Removed: ${BIN_DIR}/tlc-native"
  removed=1
fi

if [[ -d "${STDLIB_DIR}" ]]; then
  rm -rf "${STDLIB_DIR}"
  echo "    Removed: ${STDLIB_DIR}"
  removed=1
fi

echo ""
if [[ ${removed} -eq 1 ]]; then
  echo "==> Uninstall complete."
else
  echo "==> Nothing to uninstall (files not found)."
fi
