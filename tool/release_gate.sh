#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

declare -a STEP_NAMES=()
declare -a STEP_STATUS=()
FAILED=0

run_step() {
  local name="$1"
  shift
  echo "=== ${name} ==="
  if "$@"; then
    STEP_NAMES+=("$name")
    STEP_STATUS+=("PASS")
  else
    STEP_NAMES+=("$name")
    STEP_STATUS+=("FAIL")
    FAILED=1
  fi
}

skip_step() {
  local name="$1"
  local reason="$2"
  echo "=== ${name} (SKIPPED) ==="
  echo "$reason"
  STEP_NAMES+=("$name")
  STEP_STATUS+=("SKIP")
}

run_step "Render blueprint verification" bash tool/verify_render_blueprint.sh
run_step "Backend tests (dart test)" bash -lc 'cd backend && dart test'
run_step "Flutter tests (flutter test)" flutter test
run_step "Staging smoke (bash)" bash -lc 'HAILO_API_BASE_URL=https://hail-o-api-staging.onrender.com ENV=staging bash tool/smoke_backend.sh'
if [[ "${HAILO_ALLOW_PROD_SMOKE:-0}" == "1" ]]; then
  run_step "Production smoke (bash)" bash -lc 'HAILO_API_BASE_URL=https://hail-o-api.onrender.com ENV=production HAILO_ALLOW_PROD_SMOKE=1 bash tool/smoke_backend.sh'
else
  skip_step "Production smoke (bash)" "Set HAILO_ALLOW_PROD_SMOKE=1 to run production smoke."
fi

echo
echo "=== Release Gate Summary ==="
for i in "${!STEP_NAMES[@]}"; do
  printf "%-35s %s\n" "${STEP_NAMES[$i]}" "${STEP_STATUS[$i]}"
done

if [[ "$FAILED" -ne 0 ]]; then
  echo "RELEASE GATE: FAIL"
  exit 1
fi

echo "RELEASE GATE: PASS"
