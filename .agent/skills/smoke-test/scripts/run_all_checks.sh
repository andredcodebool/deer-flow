#!/usr/bin/env bash
# run_all_checks.sh — Orchestrates all smoke-test checks for deer-flow.
# Runs environment, Docker, and frontend checks in sequence and produces
# a consolidated summary report.

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="${SCRIPT_DIR}/../reports"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
REPORT_FILE="${REPORT_DIR}/smoke_test_${TIMESTAMP}.txt"

mkdir -p "${REPORT_DIR}"

# ---------------------------------------------------------------------------
# Colour helpers (disabled when not a TTY)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

log()  { echo -e "${CYAN}[INFO]${RESET}  $*" | tee -a "${REPORT_FILE}"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*" | tee -a "${REPORT_FILE}"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*" | tee -a "${REPORT_FILE}"; }
fail() { echo -e "${RED}[FAIL]${RESET}  $*" | tee -a "${REPORT_FILE}"; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
MODE="local"   # local | docker | all
EXIT_ON_FAIL=0

usage() {
  echo "Usage: $0 [--mode local|docker|all] [--exit-on-fail]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)        MODE="$2"; shift 2 ;;
    --exit-on-fail) EXIT_ON_FAIL=1; shift ;;
    -h|--help)     usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[[ "${MODE}" =~ ^(local|docker|all)$ ]] || { echo "Invalid mode: ${MODE}"; usage; }

# ---------------------------------------------------------------------------
# Run a single check script and capture its exit code
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

run_check() {
  local label="$1"
  local script="$2"

  if [[ ! -x "${script}" ]]; then
    warn "${label}: script not found or not executable — skipping (${script})"
    (( SKIP_COUNT++ )) || true
    return 0
  fi

  log "Running: ${label}"
  if bash "${script}" >> "${REPORT_FILE}" 2>&1; then
    ok "${label} passed"
    (( PASS_COUNT++ )) || true
  else
    fail "${label} FAILED (exit $?)"
    (( FAIL_COUNT++ )) || true
    if [[ "${EXIT_ON_FAIL}" -eq 1 ]]; then
      fail "Aborting early due to --exit-on-fail"
      finalize
      exit 1
    fi
  fi
}

# ---------------------------------------------------------------------------
# Print final summary and write to report
# ---------------------------------------------------------------------------
finalize() {
  echo "" | tee -a "${REPORT_FILE}"
  echo -e "${BOLD}========== Smoke-Test Summary ==========${RESET}" | tee -a "${REPORT_FILE}"
  echo -e "  Passed : ${GREEN}${PASS_COUNT}${RESET}" | tee -a "${REPORT_FILE}"
  echo -e "  Failed : ${RED}${FAIL_COUNT}${RESET}"   | tee -a "${REPORT_FILE}"
  echo -e "  Skipped: ${YELLOW}${SKIP_COUNT}${RESET}" | tee -a "${REPORT_FILE}"
  echo -e "  Report : ${REPORT_FILE}"                 | tee -a "${REPORT_FILE}"
  echo -e "${BOLD}========================================${RESET}" | tee -a "${REPORT_FILE}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo "" | tee "${REPORT_FILE}"
log "deer-flow smoke-test suite — mode=${MODE}  timestamp=${TIMESTAMP}"
echo "" | tee -a "${REPORT_FILE}"

if [[ "${MODE}" == "local" || "${MODE}" == "all" ]]; then
  run_check "Local environment check" "${SCRIPT_DIR}/check_local_env.sh"
  run_check "Local deployment check"  "${SCRIPT_DIR}/deploy_local.sh"
fi

if [[ "${MODE}" == "docker" || "${MODE}" == "all" ]]; then
  run_check "Docker environment check" "${SCRIPT_DIR}/check_docker.sh"
  run_check "Docker deployment check"  "${SCRIPT_DIR}/deploy_docker.sh"
fi

# Frontend check runs regardless of backend mode
run_check "Frontend check" "${SCRIPT_DIR}/frontend_check.sh"

finalize

# Exit non-zero if any check failed
[[ "${FAIL_COUNT}" -eq 0 ]]
