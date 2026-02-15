#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

INCLUDE_PROD="${INCLUDE_PROD:-0}"

echo "=== FAST LOCAL GATE (backend dart test) ==="
(cd backend && dart test)

echo "=== STAGING RELEASE GATE ==="
HAILO_ALLOW_PROD_SMOKE=0 bash tool/release_gate.sh

if [[ "$INCLUDE_PROD" == "1" ]]; then
  echo "=== PRODUCTION RELEASE GATE ==="
  HAILO_ALLOW_PROD_SMOKE=1 bash tool/release_gate.sh
else
  echo "=== PRODUCTION GATE SKIPPED ==="
  echo "Set INCLUDE_PROD=1 to execute production smoke gate."
fi

echo "Release workflow completed successfully."
