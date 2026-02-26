#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV_NAME="staging"
BASE_URL="${BASE_URL:-}"
BASE_STAGING="${BASE_STAGING:-${STAGING_BASE_URL:-}}"
REQUIRED_MIGRATION_HEAD="${REQUIRED_MIGRATION_HEAD:-}"
REQUIRE_PARITY="${RELEASE_GATE_REQUIRE_PARITY:-false}"
STRICT_LOCAL_AUTH="${RELEASE_GATE_STRICT_LOCAL_AUTH:-false}"

usage() {
  cat <<'EOF'
Usage: release_gate.sh --env=<staging|prod> --base=<url> [options]

Options:
  --env=<name>                     Target environment label (staging|prod)
  --base=<url>                     Target environment base URL
  --base-staging=<url>             Staging base URL (required when --env=prod)
  --required-migration-head=<num>  Optional migration head assertion
  --require-parity=<true|false>    Fail if staging/target commits differ

Environment variable fallbacks:
  BASE_URL, BASE_STAGING, STAGING_BASE_URL, REQUIRED_MIGRATION_HEAD,
  RELEASE_GATE_REQUIRE_PARITY, RELEASE_GATE_STRICT_LOCAL_AUTH.

Smoke envs:
  SMOKE_ACCESS_TOKEN
  SMOKE_PHONE_E164
  SMOKE_OTP_CODE
  SMOKE_WEBHOOK_SIM
EOF
}

normalize_bool() {
  local value="${1:-}"
  value="$(echo "$value" | tr '[:upper:]' '[:lower:]' | xargs)"
  if [[ "$value" == "1" || "$value" == "true" || "$value" == "yes" || "$value" == "y" || "$value" == "on" ]]; then
    echo "true"
    return 0
  fi
  echo "false"
}

fail() {
  echo "RELEASE GATE: FAIL - $1" >&2
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "missing required command: $1"
  fi
}

require_env() {
  local key="$1"
  local value="${!key:-}"
  if [[ -z "${value// }" ]]; then
    fail "missing required env var: ${key}"
  fi
}

check_ready() {
  local label="$1"
  local base="$2"
  local response_file
  response_file="$(mktemp)"

  local code
  code="$(curl -sS -o "$response_file" -w "%{http_code}" "${base}/ready" || true)"
  if [[ "$code" == "404" ]]; then
    code="$(curl -sS -o "$response_file" -w "%{http_code}" "${base}/api/ready" || true)"
  fi
  if [[ "$code" != "200" ]]; then
    local body
    body="$(cat "$response_file")"
    rm -f "$response_file"
    fail "${label} readiness check failed with status ${code}. body=${body}"
  fi

  local ok ready migrations_ok expected_head applied_head
  ok="$(jq -r '.ok // false' "$response_file")"
  ready="$(jq -r '.ready // .ok // false' "$response_file")"
  migrations_ok="$(jq -r '.migrations_ok // empty' "$response_file")"
  expected_head="$(jq -r '.expected_migration_head // empty' "$response_file")"
  applied_head="$(jq -r '.applied_migration_head // empty' "$response_file")"

  if [[ "$ok" != "true" || "$ready" != "true" ]]; then
    local body
    body="$(cat "$response_file")"
    rm -f "$response_file"
    fail "${label} readiness payload reports not ready. body=${body}"
  fi
  if [[ -n "$migrations_ok" && "$migrations_ok" != "true" ]]; then
    rm -f "$response_file"
    fail "${label} reports migrations_ok=${migrations_ok}"
  fi
  if [[ -n "$expected_head" && -n "$applied_head" && "$expected_head" != "$applied_head" ]]; then
    rm -f "$response_file"
    fail "${label} migration head mismatch: expected=${expected_head} applied=${applied_head}"
  fi
  if [[ -n "$REQUIRED_MIGRATION_HEAD" && -n "$applied_head" && "$REQUIRED_MIGRATION_HEAD" != "$applied_head" ]]; then
    rm -f "$response_file"
    fail "${label} migration head mismatch against required head=${REQUIRED_MIGRATION_HEAD} (applied=${applied_head})"
  fi

  rm -f "$response_file"
  echo "[release-gate] ${label} readiness check passed"
}

fetch_commit() {
  local base="$1"
  local response_file
  response_file="$(mktemp)"
  local code
  code="$(curl -sS -o "$response_file" -w "%{http_code}" "${base}/version" || true)"
  if [[ "$code" != "200" ]]; then
    rm -f "$response_file"
    echo ""
    return 0
  fi
  local commit
  commit="$(jq -r '.commit // .build.commit // empty' "$response_file")"
  rm -f "$response_file"
  echo "$commit"
}

for arg in "$@"; do
  case "$arg" in
    --env=*) ENV_NAME="${arg#*=}" ;;
    --base=*) BASE_URL="${arg#*=}" ;;
    --base-staging=*|--staging-base=*) BASE_STAGING="${arg#*=}" ;;
    --required-migration-head=*) REQUIRED_MIGRATION_HEAD="${arg#*=}" ;;
    --require-parity=*) REQUIRE_PARITY="${arg#*=}" ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: ${arg}"
      ;;
  esac
done

ENV_NAME="$(echo "$ENV_NAME" | tr '[:upper:]' '[:lower:]' | xargs)"
REQUIRE_PARITY="$(normalize_bool "$REQUIRE_PARITY")"
STRICT_LOCAL_AUTH="$(normalize_bool "$STRICT_LOCAL_AUTH")"

if [[ -z "${BASE_URL// }" ]]; then
  fail "BASE_URL is required (--base=...)"
fi
BASE_URL="${BASE_URL%/}"
BASE_STAGING="${BASE_STAGING%/}"

require_cmd curl
require_cmd jq

PAYMENTS_PROVIDER_VALUE="${PAYMENTS_PROVIDER:-${PAYMENT_PROVIDER:-}}"

if [[ "$ENV_NAME" == "prod" || "$ENV_NAME" == "production" ]]; then
  if [[ -z "${BASE_STAGING// }" ]]; then
    fail "BASE_STAGING is required for prod release gate (--base-staging=...)"
  fi
fi

if [[ "$STRICT_LOCAL_AUTH" == "true" ]]; then
  echo "[release-gate] strict local auth checks enabled"
  if [[ "$ENV_NAME" == "prod" || "$ENV_NAME" == "production" ]]; then
    require_env JWT_SECRET
    require_env OTP_PROVIDER
    require_env PAYSTACK_SECRET_KEY
    require_env PAYSTACK_WEBHOOK_SECRET
    require_env PAYMENTS_WEBHOOK_SECRET
    if [[ -z "${PAYMENTS_PROVIDER_VALUE// }" ]]; then
      fail "missing required env var: PAYMENTS_PROVIDER (or PAYMENT_PROVIDER)"
    fi
  else
    require_env JWT_SECRET
    if [[ -z "${PAYMENTS_PROVIDER_VALUE// }" ]]; then
      fail "missing required env var: PAYMENTS_PROVIDER (or PAYMENT_PROVIDER)"
    fi
  fi
else
  echo "[release-gate] strict local auth checks disabled; skipping local secret requirements"
fi

SMOKE_ACCESS_TOKEN_VALUE="${SMOKE_ACCESS_TOKEN:-${TEST_ACCESS_TOKEN:-${E2E_ACCESS_TOKEN:-}}}"
SMOKE_PHONE_VALUE="${SMOKE_PHONE_E164:-${TEST_PHONE_E164:-${E2E_PHONE_E164:-}}}"
SMOKE_OTP_VALUE="${SMOKE_OTP_CODE:-${TEST_OTP:-${E2E_OTP_CODE:-}}}"
SMOKE_WEBHOOK_SIM_VALUE="${SMOKE_WEBHOOK_SIM:-${PAYMENTS_TEST_MODE:-}}"

TARGET_LABEL="$ENV_NAME"
SMOKE_BASE="$BASE_URL"
SMOKE_ENV="$ENV_NAME"

if [[ "$ENV_NAME" == "prod" || "$ENV_NAME" == "production" ]]; then
  SMOKE_BASE="$BASE_STAGING"
  SMOKE_ENV="staging"
fi

echo "[release-gate] target_env=${ENV_NAME}"
echo "[release-gate] target_base=${BASE_URL}"
echo "[release-gate] smoke_base=${SMOKE_BASE}"
if [[ -z "${SMOKE_ACCESS_TOKEN_VALUE// }" && -z "${SMOKE_PHONE_VALUE// }" ]]; then
  echo "[release-gate] smoke auth env not provided; smoke runner will execute in skip-auth mode"
fi

check_ready "$TARGET_LABEL" "$BASE_URL"
if [[ "$SMOKE_BASE" != "$BASE_URL" ]]; then
  check_ready "staging" "$SMOKE_BASE"
fi

if [[ "$REQUIRE_PARITY" == "true" && "$SMOKE_BASE" != "$BASE_URL" ]]; then
  staging_commit="$(fetch_commit "$SMOKE_BASE")"
  target_commit="$(fetch_commit "$BASE_URL")"
  if [[ -z "$staging_commit" || -z "$target_commit" ]]; then
    fail "unable to resolve commit for parity check"
  fi
  if [[ "$staging_commit" != "$target_commit" ]]; then
    fail "commit parity check failed: staging=${staging_commit} target=${target_commit}"
  fi
  echo "[release-gate] commit parity verified: ${target_commit}"
fi

echo "[release-gate] running smoke_e2e.sh against ${SMOKE_BASE}"
(
  smoke_cmd=(
    "${ROOT_DIR}/ops/smoke_e2e.sh"
    "--base=${SMOKE_BASE}"
    "--env=${SMOKE_ENV}"
  )
  if [[ -n "${SMOKE_WEBHOOK_SIM_VALUE// }" ]]; then
    smoke_cmd+=("--smoke-webhook-sim=$(normalize_bool "${SMOKE_WEBHOOK_SIM_VALUE}")")
  fi
  if [[ -n "${SMOKE_ACCESS_TOKEN_VALUE// }" ]]; then
    smoke_cmd+=("--smoke-access-token=${SMOKE_ACCESS_TOKEN_VALUE}")
  else
    if [[ -n "${SMOKE_PHONE_VALUE// }" ]]; then
      smoke_cmd+=("--smoke-phone=${SMOKE_PHONE_VALUE}")
    fi
    if [[ -n "${SMOKE_OTP_VALUE// }" ]]; then
      smoke_cmd+=("--smoke-otp=${SMOKE_OTP_VALUE}")
    fi
  fi
  "${smoke_cmd[@]}"
)

echo "RELEASE GATE: PASS"
