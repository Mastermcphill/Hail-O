#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT_VALUE="${PORT:-18080}"
LOG_FILE="$(mktemp)"
BODY_FILE="$(mktemp)"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f "$LOG_FILE" "$BODY_FILE"
}

trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1"
    exit 2
  fi
}

assert_status() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "unexpected status for ${label}: expected=${expected} actual=${actual}"
    cat "$BODY_FILE"
    exit 1
  fi
}

extract_token() {
  sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$1"
}

require_cmd dart
require_cmd curl
require_cmd rg

cd "$ROOT_DIR"

dart --version
dart pub get
dart analyze
dart test

export BACKEND_DB_MODE="${BACKEND_DB_MODE:-sqlite}"
export PORT="$PORT_VALUE"

dart run bin/server.dart >"$LOG_FILE" 2>&1 &
SERVER_PID="$!"

for _ in $(seq 1 80); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "server exited before listen contract was observed"
    cat "$LOG_FILE"
    exit 1
  fi
  if rg -q "\"event\":\"server_listen\".*\"host\":\"0.0.0.0\".*\"port\":${PORT_VALUE}" "$LOG_FILE"; then
    break
  fi
  sleep 0.25
done

if ! rg -q "\"event\":\"server_listen\".*\"host\":\"0.0.0.0\".*\"port\":${PORT_VALUE}" "$LOG_FILE"; then
  echo "missing expected server_listen startup event"
  cat "$LOG_FILE"
  exit 1
fi

listen_count="$(rg -c "\"event\":\"server_listen\"" "$LOG_FILE" || true)"
if [[ "$listen_count" != "1" ]]; then
  echo "expected exactly one server_listen event, found ${listen_count}"
  cat "$LOG_FILE"
  exit 1
fi

status="$(curl -sS -o "$BODY_FILE" -w "%{http_code}" "http://127.0.0.1:${PORT_VALUE}/api/healthz")"
assert_status "200" "$status" "/api/healthz"
rg -q '"ok":true' "$BODY_FILE"

status="$(curl -sS -o "$BODY_FILE" -w "%{http_code}" "http://127.0.0.1:${PORT_VALUE}/healthz")"
assert_status "200" "$status" "/healthz"
rg -q '"ok":true' "$BODY_FILE"

run_id="$(date -u +%s)"
email="compile.gate.${run_id}@hailo.dev"
password="Passw0rd!"

register_payload="{\"email\":\"${email}\",\"password\":\"${password}\",\"role\":\"rider\",\"display_name\":\"Compile Gate\"}"
status="$(
  curl -sS -o "$BODY_FILE" -w "%{http_code}" \
    -X POST "http://127.0.0.1:${PORT_VALUE}/auth/register" \
    -H "Content-Type: application/json" \
    -H "Idempotency-Key: compile-gate-register-${run_id}" \
    --data "$register_payload"
)"
assert_status "201" "$status" "/auth/register"

login_payload="{\"email\":\"${email}\",\"password\":\"${password}\"}"
status="$(
  curl -sS -o "$BODY_FILE" -w "%{http_code}" \
    -X POST "http://127.0.0.1:${PORT_VALUE}/auth/login" \
    -H "Content-Type: application/json" \
    --data "$login_payload"
)"
assert_status "200" "$status" "/auth/login"
token="$(extract_token "$BODY_FILE")"
if [[ -z "$token" ]]; then
  echo "login response missing token"
  cat "$BODY_FILE"
  exit 1
fi

status="$(
  curl -sS -o "$BODY_FILE" -w "%{http_code}" \
    "http://127.0.0.1:${PORT_VALUE}/marketplace/offers" \
    -H "Authorization: Bearer ${token}"
)"
assert_status "200" "$status" "/marketplace/offers"
rg -q '"offers"' "$BODY_FILE"

status="$(
  curl -sS -o "$BODY_FILE" -w "%{http_code}" \
    "http://127.0.0.1:${PORT_VALUE}/marketplace/offers/offer_sedan_01/paywall" \
    -H "Authorization: Bearer ${token}"
)"
assert_status "200" "$status" "/marketplace/offers/{offerId}/paywall"
rg -q '"headline"' "$BODY_FILE"

echo "compile gate passed"
