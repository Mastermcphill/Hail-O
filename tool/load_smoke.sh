#!/usr/bin/env bash
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for JSON validation in load_smoke.sh"
  exit 2
fi

ENV_NAME="${ENV:-staging}"
if [[ -n "${HAILO_API_BASE_URL:-}" ]]; then
  BASE_URL="$HAILO_API_BASE_URL"
elif [[ "$ENV_NAME" == "production" ]]; then
  BASE_URL="https://hail-o-api.onrender.com"
else
  BASE_URL="https://hail-o-api-staging.onrender.com"
fi

if [[ "$BASE_URL" == "https://hail-o-api.onrender.com" && "${HAILO_ALLOW_PROD_SMOKE:-0}" != "1" ]]; then
  echo "Refusing load smoke on production without HAILO_ALLOW_PROD_SMOKE=1"
  exit 2
fi

COUNT="${LOAD_REQUESTS:-200}"
CONCURRENCY="${LOAD_CONCURRENCY:-10}"
STATUS_FILE="$(mktemp)"
trap 'rm -f "$STATUS_FILE"' EXIT

worker() {
  local idx="$1"
  local mod=$((idx % 3))
  local status
  if [[ "$mod" -eq 0 ]]; then
    status="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE_URL/health")"
  elif [[ "$mod" -eq 1 ]]; then
    status="$(curl -sS -o /dev/null -w "%{http_code}" \
      -X POST "$BASE_URL/auth/login" \
      -H "Content-Type: application/json" \
      --data '{"email":"load.invalid@hailo.dev","password":"invalid"}')"
  else
    status="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE_URL/rides/load-smoke")"
  fi
  echo "$status" >> "$STATUS_FILE"
}
export BASE_URL STATUS_FILE
export -f worker

seq 1 "$COUNT" | xargs -I{} -P "$CONCURRENCY" bash -lc 'worker "$@"' _ {}

echo "BASE_URL=$BASE_URL"
echo "LOAD_REQUESTS=$COUNT"
echo "LOAD_CONCURRENCY=$CONCURRENCY"
echo "STATUS_COUNTS:"
sort "$STATUS_FILE" | uniq -c | sed 's/^ *//'

echo
echo "RATE_LIMIT_BURST_CHECK:"
BURST_COUNT="${LOAD_BURST_REQUESTS:-${RATE_LIMIT_BURST:-25}}"
ENFORCE_BURST="${HAILO_ENFORCE_RATE_LIMIT_BURST:-0}"
EXPECTED_ENABLED="${RATE_LIMIT_ENABLED:-auto}"
RATE_LIMIT_HITS=0
for i in $(seq 1 "$BURST_COUNT"); do
  BODY_FILE="$(mktemp)"
  STATUS="$(curl -sS -o "$BODY_FILE" -w "%{http_code}" \
    -X POST "$BASE_URL/auth/login" \
    -H "Content-Type: application/json" \
    -H "X-Forwarded-For: 203.0.113.10" \
    --data '{"email":"burst.invalid@hailo.dev","password":"invalid"}')"
  if [[ "$STATUS" == "429" ]]; then
    python3 - "$BODY_FILE" <<'PY'
import json
import pathlib
import sys

raw = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
data = json.loads(raw)
if data.get("code") != "rate_limited":
    raise SystemExit("rate limit burst expected code=rate_limited")
trace_id = (data.get("trace_id") or "").strip()
if not trace_id or trace_id == "trace-unset":
    raise SystemExit("rate limit burst expected non-empty trace_id")
PY
    RATE_LIMIT_HITS=$((RATE_LIMIT_HITS + 1))
  fi
  rm -f "$BODY_FILE"
done

echo "BURST_REQUESTS=$BURST_COUNT"
echo "BURST_429_COUNT=$RATE_LIMIT_HITS"
if [[ "$RATE_LIMIT_HITS" -gt 0 ]]; then
  if [[ "$EXPECTED_ENABLED" == "0" || "$EXPECTED_ENABLED" == "false" ]]; then
    echo "Observed 429 while RATE_LIMIT_ENABLED indicates disabled."
    exit 1
  fi
  echo "RATE_LIMIT_BURST_CHECK=PASS (ENABLED)"
  exit 0
fi

if [[ "$RATE_LIMIT_HITS" -lt 1 ]]; then
  if [[ "$ENFORCE_BURST" == "1" ]]; then
    echo "Expected at least one 429 from auth burst check but got none."
    exit 1
  fi
  if [[ "$EXPECTED_ENABLED" == "1" || "$EXPECTED_ENABLED" == "true" ]]; then
    echo "RATE_LIMIT_ENABLED is true but no 429 observed during burst check."
    exit 1
  fi
  echo "RATE_LIMIT_BURST_CHECK=DISABLED (expected no 429)"
  exit 0
fi
