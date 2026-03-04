#!/usr/bin/env bash
# uninstall-linux.sh - Remove tlc installed by install-linux.sh

set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
STDLIB_DIR="${XDG_DATA_HOME}/tlc"

echo "==> Uninstalling tlc and tla-sany..."

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

if [[ -f "${BIN_DIR}/tla-sany" ]]; then
  rm -f "${BIN_DIR}/tla-sany"
  echo "    Removed: ${BIN_DIR}/tla-sany"
  removed=1
fi

if [[ -f "${BIN_DIR}/tla-sany-native" ]]; then
  rm -f "${BIN_DIR}/tla-sany-native"
  echo "    Removed: ${BIN_DIR}/tla-sany-native"
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
