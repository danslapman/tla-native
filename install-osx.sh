#!/usr/bin/env bash
# install-osx.sh - Install tlc and tlc-native to ~/.local/bin (macOS)
#
# Usage:
#   ./install-osx.sh
#
# Installs to:
#   ~/.local/bin/tlc-native          (native binary)
#   ~/.local/bin/tlc                 (wrapper script)
#   ~/Library/Application Support/tlc/tla2sany/StandardModules/  (stdlib)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY="${SCRIPT_DIR}/tlc-native"
SANY_BINARY="${SCRIPT_DIR}/tla-sany-native"
STDLIB_SRC="${SCRIPT_DIR}/tla2sany/StandardModules"

BIN_DIR="${HOME}/.local/bin"
STDLIB_DEST="${HOME}/Library/Application Support/tlc/tla2sany/StandardModules"

# ─── BUILD IF NEEDED ───────────────────────────────────────────────────────────
needs_build=0
if [[ ! -f "${BINARY}" ]]; then
  needs_build=1
elif ! file "${BINARY}" | grep -q "Mach-O"; then
  echo "==> tlc-native exists but is not a macOS (Mach-O) binary. Rebuilding..."
  needs_build=1
elif [[ ! -f "${SANY_BINARY}" ]]; then
  needs_build=1
elif ! file "${SANY_BINARY}" | grep -q "Mach-O"; then
  echo "==> tla-sany-native exists but is not a macOS (Mach-O) binary. Rebuilding..."
  needs_build=1
fi

if [[ ${needs_build} -eq 1 ]]; then
  echo "==> Running build-osx.sh..."
  echo ""
  "${SCRIPT_DIR}/build-osx.sh"
  echo ""
fi

# Verify stdlib was extracted by the build
if [[ ! -d "${STDLIB_SRC}" ]]; then
  echo "ERROR: Standard modules not found at ${STDLIB_SRC}" >&2
  echo "       Run ./build-osx.sh to build and extract them." >&2
  exit 1
fi

# ─── INSTALL ───────────────────────────────────────────────────────────────────
echo "==> Installing tlc to ${BIN_DIR}"

mkdir -p "${BIN_DIR}"
mkdir -p "${STDLIB_DEST}"

cp "${BINARY}" "${BIN_DIR}/tlc-native"
chmod +x "${BIN_DIR}/tlc-native"

cp "${SANY_BINARY}" "${BIN_DIR}/tla-sany-native"
chmod +x "${BIN_DIR}/tla-sany-native"

cp "${STDLIB_SRC}"/*.tla "${STDLIB_DEST}/"

# Write a wrapper that uses the installed absolute paths
cat > "${BIN_DIR}/tlc" << EOF
#!/usr/bin/env bash
# tlc - wrapper for tlc-native (installed by install-osx.sh)
exec "\${HOME}/.local/bin/tlc-native" "-DTLA-Library=\${HOME}/Library/Application Support/tlc/tla2sany/StandardModules" "\$@"
EOF
chmod +x "${BIN_DIR}/tlc"

cat > "${BIN_DIR}/tla-sany" << EOF
#!/usr/bin/env bash
# tla-sany - wrapper for tla-sany-native (installed by install-osx.sh)
exec "\${HOME}/.local/bin/tla-sany-native" "-DTLA-Library=\${HOME}/Library/Application Support/tlc/tla2sany/StandardModules" "\$@"
EOF
chmod +x "${BIN_DIR}/tla-sany"

# ─── PATH CHECK ────────────────────────────────────────────────────────────────
echo ""
echo "==> Install complete:"
echo "    Binary:   ${BIN_DIR}/tlc-native"
echo "    Wrapper:  ${BIN_DIR}/tlc  (use this)"
echo "    Binary:   ${BIN_DIR}/tla-sany-native"
echo "    Wrapper:  ${BIN_DIR}/tla-sany  (use this)"
echo "    Stdlib:   ${STDLIB_DEST}"
echo ""

if ! echo ":${PATH}:" | grep -q ":${BIN_DIR}:"; then
  echo "NOTE: ${BIN_DIR} is not in your PATH."
  echo "      Add the following to your shell profile (~/.zshrc or ~/.bash_profile):"
  echo ""
  echo "      export PATH=\"\${HOME}/.local/bin:\${PATH}\""
  echo ""
fi
