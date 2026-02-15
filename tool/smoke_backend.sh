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
  echo "Refusing to run smoke against production without HAILO_ALLOW_PROD_SMOKE=1"
  exit 2
fi

RUN_ID="${HAILO_SMOKE_RUN_ID:-$(date -u +%s)}"
PASSWORD="${HAILO_SMOKE_PASSWORD:-Passw0rd!}"
RIDER_EMAIL="smoke.rider.${RUN_ID}@hailo.dev"
DRIVER_EMAIL="smoke.driver.${RUN_ID}@hailo.dev"
ADMIN_EMAIL="${HAILO_ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${HAILO_ADMIN_PASSWORD:-}"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

ider() {
  local step="$1"
  echo "smoke-${RUN_ID}-${step}"
}

extract_json_string() {
  local json="$1"
  local key="$2"
  echo "$json" | sed -n "s/.*\"${key}\":\"\\([^\"]*\\)\".*/\\1/p"
}

request_json() {
  local method="$1"
  local url="$2"
  local body="$3"
  local token="${4:-}"
  local idem="${5:-}"
  local args=(-sS -X "$method" "$url" -H "Content-Type: application/json")
  if [[ -n "$token" ]]; then
    args+=(-H "Authorization: Bearer $token")
  fi
  if [[ -n "$idem" ]]; then
    args+=(-H "Idempotency-Key: $idem")
  fi
  args+=(--data "$body" -w "\nHTTP_STATUS:%{http_code}")
  curl "${args[@]}"
}

split_status() {
  local response="$1"
  STATUS="${response##*HTTP_STATUS:}"
  BODY="${response%HTTP_STATUS:*}"
}

assert_status_in() {
  local actual="$1"
  shift
  for expected in "$@"; do
    if [[ "$actual" == "$expected" ]]; then
      return 0
    fi
  done
  echo "Unexpected HTTP status: $actual (expected one of: $*)"
  echo "Body: $BODY"
  exit 1
}

echo "BASE_URL=$BASE_URL"
echo "RUN_ID=$RUN_ID"

echo
echo "=== HEALTH ==="
curl -sS -i "$BASE_URL/health"

echo
echo "=== RIDER REGISTER ==="
RIDER_REGISTER_RESPONSE="$(request_json "POST" "$BASE_URL/auth/register" "{\"email\":\"$RIDER_EMAIL\",\"password\":\"$PASSWORD\",\"role\":\"rider\",\"display_name\":\"Smoke Rider\",\"next_of_kin\":{\"full_name\":\"Smoke NOK\",\"phone\":\"+2348010000000\",\"relationship\":\"Sibling\"}}" "" "$(ider rider-register)")"
split_status "$RIDER_REGISTER_RESPONSE"
assert_status_in "$STATUS" "200" "201"
RIDER_USER_ID="$(extract_json_string "$BODY" "user_id")"
echo "status=$STATUS rider_user_id=$RIDER_USER_ID"

echo
echo "=== RIDER LOGIN ==="
RIDER_LOGIN_RESPONSE="$(request_json "POST" "$BASE_URL/auth/login" "{\"email\":\"$RIDER_EMAIL\",\"password\":\"$PASSWORD\"}")"
split_status "$RIDER_LOGIN_RESPONSE"
assert_status_in "$STATUS" "200"
RIDER_TOKEN="$(extract_json_string "$BODY" "token")"
echo "status=$STATUS rider_email=$RIDER_EMAIL"
if [[ -z "$RIDER_TOKEN" ]]; then
  echo "Missing rider token in login response"
  exit 1
fi

echo
echo "=== RIDER REQUEST RIDE ==="
RIDE_BODY="{\"scheduled_departure_at\":\"$NOW_UTC\",\"trip_scope\":\"intra_city\",\"distance_meters\":12000,\"duration_seconds\":1800,\"luggage_count\":1,\"vehicle_class\":\"sedan\",\"base_fare_minor\":100000,\"premium_markup_minor\":5000,\"connection_fee_minor\":5000}"
RIDE_RESPONSE="$(request_json "POST" "$BASE_URL/rides/request" "$RIDE_BODY" "$RIDER_TOKEN" "$(ider ride-request)")"
split_status "$RIDE_RESPONSE"
assert_status_in "$STATUS" "200" "201"
RIDE_ID="$(extract_json_string "$BODY" "ride_id")"
echo "status=$STATUS ride_id=$RIDE_ID"
if [[ -z "$RIDE_ID" ]]; then
  echo "Missing ride_id from request ride response"
  echo "$BODY"
  exit 1
fi

echo
echo "=== DRIVER REGISTER + LOGIN ==="
DRIVER_REGISTER_RESPONSE="$(request_json "POST" "$BASE_URL/auth/register" "{\"email\":\"$DRIVER_EMAIL\",\"password\":\"$PASSWORD\",\"role\":\"driver\",\"display_name\":\"Smoke Driver\"}" "" "$(ider driver-register)")"
split_status "$DRIVER_REGISTER_RESPONSE"
assert_status_in "$STATUS" "200" "201"
DRIVER_USER_ID="$(extract_json_string "$BODY" "user_id")"
DRIVER_LOGIN_RESPONSE="$(request_json "POST" "$BASE_URL/auth/login" "{\"email\":\"$DRIVER_EMAIL\",\"password\":\"$PASSWORD\"}")"
split_status "$DRIVER_LOGIN_RESPONSE"
assert_status_in "$STATUS" "200"
DRIVER_TOKEN="$(extract_json_string "$BODY" "token")"
echo "driver_user_id=$DRIVER_USER_ID login_status=$STATUS"
if [[ -z "$DRIVER_TOKEN" ]]; then
  echo "Missing driver token in login response"
  exit 1
fi

echo
echo "=== DRIVER ACCEPT RIDE + REPLAY ==="
ACCEPT_BODY='{}'
ACCEPT_KEY="$(ider ride-accept)"
ACCEPT_RESPONSE="$(request_json "POST" "$BASE_URL/rides/$RIDE_ID/accept" "$ACCEPT_BODY" "$DRIVER_TOKEN" "$ACCEPT_KEY")"
split_status "$ACCEPT_RESPONSE"
assert_status_in "$STATUS" "200"
echo "accept_status=$STATUS ride_id=$RIDE_ID"
ACCEPT_REPLAY_RESPONSE="$(request_json "POST" "$BASE_URL/rides/$RIDE_ID/accept" "$ACCEPT_BODY" "$DRIVER_TOKEN" "$ACCEPT_KEY")"
split_status "$ACCEPT_REPLAY_RESPONSE"
assert_status_in "$STATUS" "200"
echo "accept_replay_status=$STATUS"

if [[ -n "$ADMIN_EMAIL" && -n "$ADMIN_PASSWORD" ]]; then
  echo
  echo "=== ADMIN LOGIN ==="
  ADMIN_LOGIN_RESPONSE="$(request_json "POST" "$BASE_URL/auth/login" "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}")"
  split_status "$ADMIN_LOGIN_RESPONSE"
  assert_status_in "$STATUS" "200"
  ADMIN_TOKEN="$(extract_json_string "$BODY" "token")"
  if [[ -z "$ADMIN_TOKEN" ]]; then
    echo "Missing admin token in login response"
    exit 1
  fi
  echo "admin_login_status=$STATUS"

  echo
  echo "=== DISPUTE OPEN + RESOLVE ==="
  OPEN_DISPUTE_RESPONSE="$(request_json "POST" "$BASE_URL/disputes" "{\"ride_id\":\"$RIDE_ID\",\"reason\":\"smoke_test\"}" "$ADMIN_TOKEN" "$(ider dispute-open)")"
  split_status "$OPEN_DISPUTE_RESPONSE"
  assert_status_in "$STATUS" "200" "201"
  DISPUTE_ID="$(extract_json_string "$BODY" "dispute_id")"
  echo "dispute_open_status=$STATUS dispute_id=$DISPUTE_ID"
  if [[ -n "$DISPUTE_ID" ]]; then
    RESOLVE_KEY="$(ider dispute-resolve)"
    RESOLVE_RESPONSE="$(request_json "POST" "$BASE_URL/disputes/$DISPUTE_ID/resolve" "{\"refund_minor\":0,\"resolution_note\":\"smoke_resolve\"}" "$ADMIN_TOKEN" "$RESOLVE_KEY")"
    split_status "$RESOLVE_RESPONSE"
    assert_status_in "$STATUS" "200"
    echo "dispute_resolve_status=$STATUS"
  fi

  echo
  echo "=== ADMIN REVERSAL + REPLAY CHECK ==="
  REVERSAL_KEY="$(ider admin-reversal)"
  REVERSAL_BODY="{\"original_ledger_id\":${HAILO_REVERSAL_LEDGER_ID:-999999999},\"reason\":\"smoke_reversal\"}"
  REVERSAL_RESPONSE_1="$(request_json "POST" "$BASE_URL/admin/reversal" "$REVERSAL_BODY" "$ADMIN_TOKEN" "$REVERSAL_KEY")"
  split_status "$REVERSAL_RESPONSE_1"
  REVERSAL_STATUS_1="$STATUS"
  REVERSAL_RESPONSE_2="$(request_json "POST" "$BASE_URL/admin/reversal" "$REVERSAL_BODY" "$ADMIN_TOKEN" "$REVERSAL_KEY")"
  split_status "$REVERSAL_RESPONSE_2"
  REVERSAL_STATUS_2="$STATUS"
  echo "reversal_status_first=$REVERSAL_STATUS_1 reversal_status_replay=$REVERSAL_STATUS_2"
  if [[ "$REVERSAL_STATUS_1" != "$REVERSAL_STATUS_2" ]]; then
    echo "Reversal replay status mismatch"
    exit 1
  fi
else
  echo
  echo "=== ADMIN FLOW SKIPPED ==="
  echo "Set HAILO_ADMIN_EMAIL and HAILO_ADMIN_PASSWORD to run admin smoke flow."
fi

echo
echo "Smoke suite completed successfully."
