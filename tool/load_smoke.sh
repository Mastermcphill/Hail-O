#!/usr/bin/env bash
set -euo pipefail

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
