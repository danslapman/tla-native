#!/usr/bin/env bash
# install-linux.sh - Install tlc and tlc-native to ~/.local/bin (Linux)
#
# Usage:
#   ./install-linux.sh
#
# Installs to:
#   ~/.local/bin/tlc-native          (native binary)
#   ~/.local/bin/tlc                 (wrapper script)
#   ~/.local/share/tlc/tla2sany/StandardModules/  (stdlib, XDG data dir)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY="${SCRIPT_DIR}/target/tlc-native"
SANY_BINARY="${SCRIPT_DIR}/target/tla-sany-native"
STDLIB_SRC="${SCRIPT_DIR}/target/tla2sany/StandardModules"

BIN_DIR="${HOME}/.local/bin"
XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
STDLIB_DEST="${XDG_DATA_HOME}/tlc/tla2sany/StandardModules"

# ─── BUILD IF NEEDED ───────────────────────────────────────────────────────────
if [[ ! -f "${BINARY}" ]] || [[ ! -f "${SANY_BINARY}" ]]; then
  echo "==> tlc-native or tla-sany-native not found. Running build-linux.sh first..."
  echo ""
  "${SCRIPT_DIR}/build-linux.sh"
  echo ""
fi

# Verify stdlib was extracted by the build
if [[ ! -d "${STDLIB_SRC}" ]]; then
  echo "ERROR: Standard modules not found at ${STDLIB_SRC}" >&2
  echo "       Run ./build-linux.sh to build and extract them." >&2
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
# tlc - wrapper for tlc-native (installed by install-linux.sh)
exec "\${HOME}/.local/bin/tlc-native" "-DTLA-Library=\${XDG_DATA_HOME:-\${HOME}/.local/share}/tlc/tla2sany/StandardModules" "\$@"
EOF
chmod +x "${BIN_DIR}/tlc"

cat > "${BIN_DIR}/tla-sany" << EOF
#!/usr/bin/env bash
# tla-sany - wrapper for tla-sany-native (installed by install-linux.sh)
exec "\${HOME}/.local/bin/tla-sany-native" "-DTLA-Library=\${XDG_DATA_HOME:-\${HOME}/.local/share}/tlc/tla2sany/StandardModules" "\$@"
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
  echo "      Add the following to your shell profile (~/.bashrc or ~/.profile):"
  echo ""
  echo "      export PATH=\"\${HOME}/.local/bin:\${PATH}\""
  echo ""
fi
