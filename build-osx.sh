#!/usr/bin/env bash
# build-osx.sh - Build tlc2.TLC as a GraalVM native executable (macOS)
#
# Usage:
#   ./build-osx.sh           # build native image (uses graal-config/ if present)
#   ./build-osx.sh --trace   # run TLC with native-image-agent to collect config
#   ./build-osx.sh --build   # same as default
#   BUILD_MEMORY=12g ./build-osx.sh  # customize build-time heap (default: 8g)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAR="${SCRIPT_DIR}/tla2tools.jar"
BINARY="${SCRIPT_DIR}/tlc-native"          # actual compiled binary
WRAPPER="${SCRIPT_DIR}/tlc"                # shell wrapper that sets -libdir
SANY_BINARY="${SCRIPT_DIR}/tla-sany-native"
SANY_WRAPPER="${SCRIPT_DIR}/tla-sany"
STDLIB_DIR="${SCRIPT_DIR}/tla2sany/StandardModules"
CONFIG_DIR="${SCRIPT_DIR}/graal-config"
TRACE_SPEC="${SCRIPT_DIR}/HelloWorld"
BUILD_MEMORY="${BUILD_MEMORY:-8g}"

# Resolve java and native-image from JAVA_HOME or PATH
if [[ -n "${JAVA_HOME:-}" ]]; then
  JAVA_BIN="${JAVA_HOME}/bin/java"
  NATIVE_IMAGE_BIN="${JAVA_HOME}/bin/native-image"
else
  JAVA_BIN="$(command -v java)"
  NATIVE_IMAGE_BIN="$(command -v native-image)"
fi

# Verify prerequisites
if [[ ! -f "${JAR}" ]]; then
  echo "ERROR: tla2tools.jar not found at ${JAR}" >&2
  exit 1
fi
if [[ ! -x "${NATIVE_IMAGE_BIN}" ]]; then
  echo "ERROR: native-image not found. Is GraalVM in JAVA_HOME or PATH?" >&2
  exit 1
fi

# ─── TRACE MODE ────────────────────────────────────────────────────────────────
do_trace() {
  echo "==> Trace mode: running TLC under native-image-agent"
  echo "    JAR:     ${JAR}"
  echo "    Spec:    ${TRACE_SPEC}.tla"
  echo "    Config:  ${CONFIG_DIR}"
  echo ""

  if [[ ! -f "${TRACE_SPEC}.tla" ]]; then
    echo "ERROR: ${TRACE_SPEC}.tla not found." >&2
    echo "       HelloWorld.tla must be alongside build-osx.sh." >&2
    exit 1
  fi

  mkdir -p "${CONFIG_DIR}"
  local STATES_DIR="${SCRIPT_DIR}/states-trace"
  mkdir -p "${STATES_DIR}"

  # TLC may exit non-zero (e.g. deadlock detected) - that's fine for tracing
  set +e
  "${JAVA_BIN}" \
    "-agentlib:native-image-agent=config-merge-dir=${CONFIG_DIR}" \
    -cp "${JAR}" \
    tlc2.TLC \
    -workers 1 \
    -cleanup \
    -checkpoint 0 \
    -metadir "${STATES_DIR}" \
    "${TRACE_SPEC}"
  set -e

  # Clean up trace state dir
  rm -rf "${STATES_DIR}"

  echo ""
  echo "==> Trace complete. Configuration written to: ${CONFIG_DIR}"
  echo "    Files:"
  ls -la "${CONFIG_DIR}/"
  echo ""
  echo "    Run './build-osx.sh' to build the native image."
}

# ─── BUILD MODE ────────────────────────────────────────────────────────────────
do_build() {
  echo "==> Build mode: compiling TLC native image"
  echo "    JAR:    ${JAR}"
  echo "    Binary: ${BINARY}"
  echo "    Heap:   ${BUILD_MEMORY} (override with BUILD_MEMORY=Xg)"
  echo ""

  # Common flags (independent of whether we have traced config)
  local -a COMMON_FLAGS=(
    # Heap for the native-image compiler JVM (not the resulting binary)
    "-J-Xmx${BUILD_MEMORY}"

    # Refuse to produce a fallback JVM-wrapper; fail hard if native is impossible
    "--no-fallback"

    # Unlock experimental H: options used below
    "-H:+UnlockExperimentalVMOptions"

    # CommunityModules.jar is declared in MANIFEST.MF Class-Path but absent.
    # Allow the static analyzer to proceed without it.
    "-H:+AllowIncompleteClasspath"

    # Defer "class not found" errors for CommunityModules references to runtime,
    # rather than aborting the build.
    "-H:+ReportUnsupportedElementsAtRuntime"

    # Embed TLA standard module files as native image resources.
    # SANY loads these via Class.getResourceAsStream() during spec parsing.
    # Regex note: native-image uses Java regex; '.' must be '\.' -> '\\.' in shell.
    "-H:IncludeResources=tla2sany/StandardModules/.*\\.tla"
    "-H:IncludeResources=pcal/.*\\.cfg"
    "-H:IncludeResources=pcal/.*\\.txt"
    "-H:IncludeResources=tlc2/output/messages\\.properties"
    "-H:IncludeResources=tlc2/value/impl/SubsetValue\\.tla"

    # JavaMail metadata (TLC email notification feature)
    "-H:IncludeResources=META-INF/javamail\\..*"
    "-H:IncludeResources=META-INF/mailcap"

    # Distributed TLC uses RMI with network-dependent class initialization.
    # Mark the whole package for runtime initialization to avoid build-time failures.
    "--initialize-at-run-time=tlc2.tool.distributed"

    # TLC can load specs over https (remote module resolution)
    "--enable-url-protocols=http,https"

    # Output binary name (the actual native binary; a wrapper script named 'tlc' is created after)
    "-o" "${BINARY}"
  )

  # Determine how to specify the input and metadata.
  # GraalVM 24 agent writes reachability-metadata.json. native-image auto-discovers
  # config placed under META-INF/native-image/ on the classpath.
  # When we have traced metadata, switch from -jar to -cp + main class so we can
  # put a staging directory (containing META-INF/native-image/) on the classpath.
  local METADATA_FILE="${CONFIG_DIR}/reachability-metadata.json"
  local STAGING_DIR="${SCRIPT_DIR}/.graal-meta-staging"

  local -a FLAGS=("${COMMON_FLAGS[@]}")

  if [[ -f "${METADATA_FILE}" ]]; then
    echo "    Using traced config from: ${METADATA_FILE}"
    local META_DIR="${STAGING_DIR}/META-INF/native-image"
    mkdir -p "${META_DIR}"
    cp "${METADATA_FILE}" "${META_DIR}/reachability-metadata.json"
    FLAGS+=("-cp" "${JAR}:${STAGING_DIR}" "tlc2.TLC")
  else
    if [[ -d "${CONFIG_DIR}" ]]; then
      echo "    Using traced config dir (legacy format): ${CONFIG_DIR}"
      FLAGS+=("-H:ConfigurationFileDirectories=${CONFIG_DIR}")
    else
      echo "    WARNING: ${CONFIG_DIR} not found."
      echo "    No agent-traced reflection config will be included."
      echo "    Run './build-osx.sh --trace' first for best results."
      echo ""
    fi
    FLAGS+=("-jar" "${JAR}")
  fi

  "${NATIVE_IMAGE_BIN}" "${FLAGS[@]}"

  # Extract TLA+ standard module files from the JAR.
  # TLC's SimpleFilenameToStream cannot resolve the 'resource:' URI scheme used
  # by GraalVM native image, so embedded resources won't be found as files.
  # Extracting them to a known directory and passing -libdir at runtime fixes this.
  echo ""
  echo "==> Extracting TLA+ standard modules..."
  mkdir -p "${STDLIB_DIR}"
  unzip -jo "${JAR}" 'tla2sany/StandardModules/*.tla' -d "${STDLIB_DIR}"
  echo "    Extracted to: ${STDLIB_DIR}"

  # Create a thin wrapper script 'tlc' that injects -libdir automatically.
  echo ""
  echo "==> Creating wrapper script: ${WRAPPER}"
  cat > "${WRAPPER}" << 'WRAPPER_EOF'
#!/usr/bin/env bash
# tlc - wrapper for tlc-native that provides the TLA+ standard library path.
# TLC's SimpleFilenameToStream reads the TLA-Library system property to find
# standard modules; we inject it here so the binary is self-contained from
# the user's perspective.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/tlc-native" "-DTLA-Library=${SCRIPT_DIR}/tla2sany/StandardModules" "$@"
WRAPPER_EOF
  chmod +x "${WRAPPER}"

  echo ""
  echo "==> Build complete (TLC):"
  echo "    Native binary: ${BINARY}"
  echo "    Wrapper:       ${WRAPPER}  (use this)"
  echo "    Standard lib:  ${STDLIB_DIR}"
  echo ""
  echo "    Quick test:  ${WRAPPER} HelloWorld"
  echo "    Full usage:  ${WRAPPER} -workers auto -config MySpec.cfg MySpec"

  # ── Build SANY native image ──────────────────────────────────────────────────
  echo ""
  echo "==> Build mode: compiling SANY native image"
  echo "    JAR:    ${JAR}"
  echo "    Binary: ${SANY_BINARY}"
  echo "    Heap:   ${BUILD_MEMORY} (override with BUILD_MEMORY=Xg)"
  echo ""

  # Copy COMMON_FLAGS minus the trailing "-o" "${BINARY}", then add SANY output path
  local _n=${#COMMON_FLAGS[@]}
  local -a SANY_FLAGS=("${COMMON_FLAGS[@]:0:$((_n-2))}")
  SANY_FLAGS+=("-o" "${SANY_BINARY}")

  if [[ -f "${METADATA_FILE}" ]]; then
    SANY_FLAGS+=("-cp" "${JAR}:${STAGING_DIR}" "tla2sany.SANY")
  else
    SANY_FLAGS+=("-cp" "${JAR}" "tla2sany.SANY")
  fi

  "${NATIVE_IMAGE_BIN}" "${SANY_FLAGS[@]}"

  # Create a thin wrapper script 'tla-sany' that injects -DTLA-Library automatically.
  echo ""
  echo "==> Creating wrapper script: ${SANY_WRAPPER}"
  cat > "${SANY_WRAPPER}" << 'SANY_WRAPPER_EOF'
#!/usr/bin/env bash
# tla-sany - wrapper for tla-sany-native that provides the TLA+ standard library path.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/tla-sany-native" "-DTLA-Library=${SCRIPT_DIR}/tla2sany/StandardModules" "$@"
SANY_WRAPPER_EOF
  chmod +x "${SANY_WRAPPER}"

  echo ""
  echo "==> Build complete (SANY):"
  echo "    Native binary: ${SANY_BINARY}"
  echo "    Wrapper:       ${SANY_WRAPPER}  (use this)"
  echo "    Standard lib:  ${STDLIB_DIR}"
  echo ""
  echo "    Quick test:  ${SANY_WRAPPER} HelloWorld.tla"
}

# ─── DISPATCH ──────────────────────────────────────────────────────────────────
case "${1:-build}" in
  --trace)        do_trace  ;;
  --build | build) do_build ;;
  *)
    echo "Usage: $0 [--trace|--build]" >&2
    echo "  --trace   run TLC under native-image-agent to collect reflection config" >&2
    echo "  --build   build the native image (default)" >&2
    exit 1
    ;;
esac
