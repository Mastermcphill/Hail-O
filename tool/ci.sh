#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "${CI_NIGHTLY_GATE:-0}" == "1" ]]; then
  INTERVAL_SECONDS="${CI_NIGHTLY_INTERVAL_SECONDS:-86400}"
  if ! [[ "$INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || [[ "$INTERVAL_SECONDS" -le 0 ]]; then
    echo "CI_NIGHTLY_INTERVAL_SECONDS must be a positive integer, got: $INTERVAL_SECONDS"
    exit 2
  fi

  echo "CI nightly staging release gate mode enabled (interval=${INTERVAL_SECONDS}s)"
  while true; do
    echo "=== NIGHTLY RELEASE GATE RUN ($(date -u +%Y-%m-%dT%H:%M:%SZ)) ==="
    powershell -ExecutionPolicy Bypass -File ./tool/ci_nightly_gate.ps1
    sleep "$INTERVAL_SECONDS"
  done
fi

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
