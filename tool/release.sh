#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

INCLUDE_PROD="${INCLUDE_PROD:-0}"
INCLUDE_LOAD_SMOKE="${INCLUDE_LOAD_SMOKE:-0}"
STRICT_LOAD_SMOKE="${STRICT_LOAD_SMOKE:-0}"

echo "=== FAST LOCAL GATE (backend pub get + analyze + test + contract) ==="
(cd backend && dart pub get && dart analyze && dart test && dart run tool/check_contract_breaking.dart)

echo "=== STAGING RELEASE GATE ==="
HAILO_ALLOW_PROD_SMOKE=0 bash tool/release_gate.sh

if [[ "$INCLUDE_LOAD_SMOKE" == "1" ]]; then
  echo "=== STAGING LOAD SMOKE ==="
  HAILO_API_BASE_URL=https://hail-o-api-staging.onrender.com ENV=staging HAILO_ENFORCE_RATE_LIMIT_BURST="$STRICT_LOAD_SMOKE" bash tool/load_smoke.sh
else
  echo "=== STAGING LOAD SMOKE SKIPPED ==="
  echo "Set INCLUDE_LOAD_SMOKE=1 to execute staging load smoke."
fi

if [[ "$INCLUDE_PROD" == "1" ]]; then
  echo "=== PRODUCTION RELEASE GATE ==="
  HAILO_ALLOW_PROD_SMOKE=1 bash tool/release_gate.sh
else
  echo "=== PRODUCTION GATE SKIPPED ==="
  echo "Set INCLUDE_PROD=1 to execute production smoke gate."
fi

echo "Release workflow completed successfully."
