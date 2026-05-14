#!/usr/bin/env bash
# validate_config.sh — Validates required configuration files and environment variables
# for the deer-flow application before running smoke tests.
#
# Usage: ./validate_config.sh [--strict]
#   --strict: Treat warnings as errors (exit 1 on any issue)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

STRICT=false
ERRORS=0
WARNINGS=0

for arg in "$@"; do
  case $arg in
    --strict) STRICT=true ;;
  esac
done

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; ((WARNINGS++)) || true; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; ((ERRORS++)) || true; }

# ---------------------------------------------------------------------------
# 1. Required files
# ---------------------------------------------------------------------------
log_info "Checking required configuration files..."

REQUIRED_FILES=(
  ".env"
  "docker-compose.yml"
  "pyproject.toml"
  "conf.yaml"
)

for f in "${REQUIRED_FILES[@]}"; do
  full="${PROJECT_ROOT}/${f}"
  if [[ -f "$full" ]]; then
    log_ok "Found: ${f}"
  else
    # .env is critical; others are warnings unless --strict
    if [[ "$f" == ".env" ]]; then
      log_error "Missing required file: ${f}  (copy .env.example and fill in values)"
    else
      log_warn "Missing expected file: ${f}"
    fi
  fi
done

# ---------------------------------------------------------------------------
# 2. Required environment variables (read from .env if present)
# ---------------------------------------------------------------------------
log_info "Checking required environment variables..."

ENV_FILE="${PROJECT_ROOT}/.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
fi

REQUIRED_VARS=(
  "OPENAI_API_KEY"
  "TAVILY_API_KEY"
)

OPTIONAL_VARS=(
  "OPENAI_BASE_URL"
  "REASONING_MODEL"
  "BASIC_MODEL"
  "VISION_MODEL"
)

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -n "${!var:-}" ]]; then
    # Mask the value — show only first 6 chars
    masked="${!var:0:6}..."
    log_ok "${var} is set (${masked})"
  else
    log_error "Required env var not set: ${var}"
  fi
done

for var in "${OPTIONAL_VARS[@]}"; do
  if [[ -n "${!var:-}" ]]; then
    log_ok "${var} is set"
  else
    log_warn "Optional env var not set: ${var}  (default will be used)"
  fi
done

# ---------------------------------------------------------------------------
# 3. conf.yaml sanity check (key presence, not value correctness)
# ---------------------------------------------------------------------------
CONF_FILE="${PROJECT_ROOT}/conf.yaml"
if [[ -f "$CONF_FILE" ]]; then
  log_info "Checking conf.yaml structure..."
  for key in "llm" "search"; do
    if grep -q "^${key}:" "$CONF_FILE" 2>/dev/null; then
      log_ok "conf.yaml has top-level key: ${key}"
    else
      log_warn "conf.yaml missing expected top-level key: ${key}"
    fi
  done
fi

# ---------------------------------------------------------------------------
# 4. Summary
# ---------------------------------------------------------------------------
echo ""
echo "─────────────────────────────────────────"
echo -e "  Errors   : ${RED}${ERRORS}${NC}"
echo -e "  Warnings : ${YELLOW}${WARNINGS}${NC}"
echo "─────────────────────────────────────────"

if [[ "$ERRORS" -gt 0 ]]; then
  log_error "Config validation FAILED — fix errors above before proceeding."
  exit 1
fi

if [[ "$STRICT" == true && "$WARNINGS" -gt 0 ]]; then
  log_error "Strict mode: treating ${WARNINGS} warning(s) as errors."
  exit 1
fi

log_ok "Config validation passed."
exit 0
