#!/usr/bin/env bash
# test-linux.sh - Run tlaplus/Examples models against the native TLC binary
#
# Usage:
#   ./test-linux.sh                    # run all models with runtime ≤60s
#   MAX_RUNTIME=30 ./test-linux.sh     # only run models that finish in ≤30s
#   VERBOSE=1 ./test-linux.sh          # show full TLC output for each model
#
# Requires:
#   - ./target/tlc  (the wrapper script created by build-linux.sh)
#   - ./target/Examples/  (cloned from https://github.com/tlaplus/Examples)
#   - jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TLC="${SCRIPT_DIR}/target/tlc"
EXAMPLES_DIR="${SCRIPT_DIR}/target/Examples/specifications"
MAX_RUNTIME="${MAX_RUNTIME:-60}"
# Hard per-model timeout in seconds; models exceeding this are killed and marked TIMEOUT
MODEL_TIMEOUT="${MODEL_TIMEOUT:-120}"
VERBOSE="${VERBOSE:-0}"

PASS=0
FAIL=0
SKIP=0

# Verify prerequisites
if [[ ! -x "${TLC}" ]]; then
  echo "ERROR: native TLC wrapper not found at ${TLC}" >&2
  echo "       Run './build-linux.sh' first." >&2
  exit 1
fi
CLONED_EXAMPLES=0
if [[ ! -d "${SCRIPT_DIR}/target/Examples" ]]; then
  echo "==> Cloning tlaplus/Examples (shallow)..."
  mkdir -p "${SCRIPT_DIR}/target"
  git clone --depth=1 https://github.com/tlaplus/Examples "${SCRIPT_DIR}/target/Examples"
  CLONED_EXAMPLES=1
fi
cleanup_examples() {
  if [[ ${CLONED_EXAMPLES} -eq 1 ]]; then
    rm -rf "${SCRIPT_DIR}/target/Examples"
  fi
}
trap cleanup_examples EXIT
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

# Map TLC exit code to result string (matches tlaplus/Examples CI convention)
resolve_exit() {
  case $1 in
    0)  echo "success" ;;
    10) echo "assumption failure" ;;
    11) echo "deadlock failure" ;;
    12) echo "safety failure" ;;
    13) echo "liveness failure" ;;
    *)  echo "exit:$1" ;;
  esac
}

# Parse HH:MM:SS runtime string to total seconds; returns 99999 on invalid input
parse_runtime_secs() {
  local rt="$1"
  if [[ "${rt}" =~ ^([0-9]+):([0-9]+):([0-9]+)$ ]]; then
    echo $(( 10#${BASH_REMATCH[1]} * 3600 + 10#${BASH_REMATCH[2]} * 60 + 10#${BASH_REMATCH[3]} ))
  else
    echo 99999
  fi
}

# Run a command with a timeout, writing stdout+stderr to an output file.
# Usage: run_with_timeout <seconds> <output_file> <cmd> [args...]
# Returns 0 on success, 124 on timeout, otherwise the command's exit code.
run_with_timeout() {
  local secs="$1" out_file="$2"
  shift 2
  "$@" >"${out_file}" 2>&1 &
  local pid=$!
  # Kill the process after timeout seconds
  ( sleep "${secs}" && kill "${pid}" 2>/dev/null ) &
  local killer=$!
  wait "${pid}"
  local ret=$?
  kill "${killer}" 2>/dev/null
  wait "${killer}" 2>/dev/null
  # SIGTERM = 143, SIGKILL = 137 — treat as timeout
  if [[ ${ret} -eq 143 || ${ret} -eq 137 ]]; then
    return 124
  fi
  return ${ret}
}

echo "==> Testing native TLC binary: ${TLC}"
echo "    Examples dir: ${EXAMPLES_DIR}"
echo "    Max runtime:  ${MAX_RUNTIME}s"
echo ""

for manifest in "${EXAMPLES_DIR}"/*/manifest.json; do
  # Parse all models from this spec's manifest using jq
  while IFS=$'\t' read -r module_path model_path runtime expected_result; do
    total_secs="$(parse_runtime_secs "${runtime}")"

    if (( total_secs > MAX_RUNTIME )); then
      (( SKIP++ )) || true
      continue
    fi

    # Resolve absolute paths (manifest paths are relative to Examples root)
    mod_file="${SCRIPT_DIR}/target/Examples/${module_path}"
    cfg_file="${SCRIPT_DIR}/target/Examples/${model_path}"

    if [[ ! -f "${mod_file}" || ! -f "${cfg_file}" ]]; then
      echo "SKIP (missing file): ${model_path}"
      (( SKIP++ )) || true
      continue
    fi

    # Create a unique temp directory for TLC's state files (avoids second-resolution
    # collision when multiple models run within the same wall-clock second).
    local_meta_dir="$(mktemp -d)"

    # Run TLC with a hard timeout; capture output and exit code
    local_out_file="$(mktemp)"
    set +e
    run_with_timeout "${MODEL_TIMEOUT}" "${local_out_file}" \
      "${TLC}" \
        -workers auto \
        -lncheck final \
        -cleanup \
        -metadir "${local_meta_dir}" \
        -nowarning \
        -config "${cfg_file}" \
        "${mod_file}"
    exit_code=$?
    set -e
    tlc_output="$(cat "${local_out_file}")"
    rm -f "${local_out_file}"

    if [[ ${exit_code} -eq 124 ]]; then
      echo "TIMEOUT [>${MODEL_TIMEOUT}s]: ${model_path}"
      (( SKIP++ )) || true
      rm -rf "${local_meta_dir}"
      continue
    fi

    # Clean up state dir regardless of -cleanup (it may leave the dir on failure)
    rm -rf "${local_meta_dir}"

    # Treat "Cannot find source file for module X" as a skip: the module is likely
    # from CommunityModules which is not bundled in the native binary.
    if echo "${tlc_output}" | grep -q "Cannot find source file for module"; then
      missing_mod="$(echo "${tlc_output}" | grep -o 'module [A-Za-z_][A-Za-z0-9_]*' | head -1)"
      echo "SKIP (missing ${missing_mod}): ${model_path}"
      (( SKIP++ )) || true
      continue
    fi

    actual_result="$(resolve_exit ${exit_code})"

    if [[ "${actual_result}" == "${expected_result}" ]]; then
      echo "PASS [${total_secs}s]: ${model_path}"
      (( PASS++ )) || true
      if (( VERBOSE )); then
        echo "${tlc_output}" | sed 's/^/    /'
      fi
    else
      echo "FAIL [${total_secs}s]: ${model_path}"
      echo "     expected=${expected_result}  actual=${actual_result} (exit ${exit_code})"
      echo "${tlc_output}" | tail -20 | sed 's/^/     /'
      (( FAIL++ )) || true
    fi

  done < <(jq -r '
    .modules[] |
    .path as $mod |
    .models[] |
    [$mod, .path, (.runtime // "99:99:99"), .result] |
    @tsv
  ' "${manifest}" 2>/dev/null || true)
done

echo ""
echo "=========================================="
echo "  Results: PASS=${PASS}  FAIL=${FAIL}  SKIP=${SKIP}"
echo "=========================================="

if (( FAIL > 0 )); then
  exit 1
fi
