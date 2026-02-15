#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

MODE="FAST"
if [[ "${CI_FULL:-0}" == "1" ]]; then
  MODE="FULL"
fi

echo "CI mode: ${MODE}"
dart --version

echo "=== BACKEND DEPENDENCIES ==="
(cd backend && dart pub get)

echo "=== BACKEND ANALYZE ==="
(cd backend && dart analyze)

echo "=== BACKEND TESTS ==="
(cd backend && dart test)

if [[ "$MODE" == "FULL" ]]; then
  if ! command -v flutter >/dev/null 2>&1; then
    echo "flutter is required for CI_FULL=1 but was not found in PATH"
    exit 2
  fi
  echo "=== FLUTTER TESTS ==="
  flutter test
fi
