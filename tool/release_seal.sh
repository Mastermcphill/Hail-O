#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "=== BACKEND TESTS ==="
(cd backend && dart test)

echo "=== FLUTTER TESTS ==="
flutter test

echo "=== STAGING SMOKE ==="
HAILO_API_BASE_URL="${HAILO_API_BASE_URL:-https://hail-o-api-staging.onrender.com}" \
  bash tool/smoke_backend.sh

if [[ "${HAILO_ALLOW_PROD_SMOKE:-0}" == "1" ]]; then
  echo "=== PROD HEALTH SMOKE ==="
  curl -sS -i https://hail-o-api.onrender.com/health
fi

echo "Release seal completed."
