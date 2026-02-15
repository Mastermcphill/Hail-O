#!/usr/bin/env bash
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for robust JSON parsing in smoke_backend.sh"
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
  echo "Refusing to run smoke against production without HAILO_ALLOW_PROD_SMOKE=1"
  exit 2
fi

RUN_ID="${HAILO_SMOKE_RUN_ID:-$(date -u +%s)}"
PASSWORD="${HAILO_SMOKE_PASSWORD:-Passw0rd!}"
RIDER_EMAIL="smoke.rider.${RUN_ID}@hailo.dev"
DRIVER_EMAIL="smoke.driver.${RUN_ID}@hailo.dev"
ADMIN_EMAIL="${HAILO_ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${HAILO_ADMIN_PASSWORD:-}"
REVERSAL_LEDGER_ID="${HAILO_REVERSAL_LEDGER_ID:-}"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

idem() {
  local step="$1"
  echo "smoke-${RUN_ID}-${step}"
}

assert_true() {
  local condition="$1"
  local message="$2"
  if [[ "$condition" != "1" ]]; then
    echo "$message"
    exit 1
  fi
}

json_validate_file() {
  local body_path="$1"
  if ! python3 - "$body_path" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
raw = path.read_text(encoding="utf-8")
json.loads(raw)
PY
  then
    echo "Expected JSON response, got:"
    cat "$body_path"
    exit 1
  fi
}

json_field() {
  local body_path="$1"
  local field="$2"
  python3 - "$body_path" "$field" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
value = data.get(sys.argv[2], "")
if value is None:
    value = ""
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

request_json() {
  local method="$1"
  local url="$2"
  local body="${3:-}"
  local token="${4:-}"
  local idem_key="${5:-}"
  local trace_id="${6:-}"
  local allowed_status_csv="${7:-200,201}"

  local header_file
  local body_file
  local payload_file=""
  header_file="$(mktemp)"
  body_file="$(mktemp)"

  local args=(-sS --fail-with-body -X "$method" "$url" -H "Accept: application/json" -D "$header_file" -o "$body_file")
  if [[ -n "$body" ]]; then
    payload_file="$(mktemp)"
    printf "%s" "$body" >"$payload_file"
    args+=(-H "Content-Type: application/json" --data-binary "@${payload_file}")
  fi
  if [[ -n "$token" ]]; then
    args+=(-H "Authorization: Bearer ${token}")
  fi
  if [[ -n "$idem_key" ]]; then
    args+=(-H "Idempotency-Key: ${idem_key}")
  fi
  if [[ -n "$trace_id" ]]; then
    args+=(-H "X-Trace-Id: ${trace_id}")
  fi

  curl "${args[@]}"

  RESPONSE_STATUS="$(awk '/^HTTP\/[0-9.]+ [0-9]{3}/{code=$2} END{print code}' "$header_file")"
  RESPONSE_BODY_FILE="$body_file"
  RESPONSE_HEADER_FILE="$header_file"

  if [[ -z "$RESPONSE_STATUS" ]]; then
    echo "Unable to parse HTTP status for $method $url"
    cat "$body_file"
    exit 1
  fi

  local status_ok=0
  IFS=',' read -r -a allowed_statuses <<<"$allowed_status_csv"
  for code in "${allowed_statuses[@]}"; do
    if [[ "$RESPONSE_STATUS" == "$code" ]]; then
      status_ok=1
      break
    fi
  done
  if [[ $status_ok -ne 1 ]]; then
    echo "Unexpected HTTP status $RESPONSE_STATUS for $method $url (expected one of $allowed_status_csv)"
    cat "$body_file"
    exit 1
  fi

  json_validate_file "$body_file"
  RESPONSE_BODY="$(cat "$body_file")"

  if [[ -n "$payload_file" ]]; then
    rm -f "$payload_file"
  fi
}

cleanup_response_files() {
  rm -f "${RESPONSE_BODY_FILE:-}" "${RESPONSE_HEADER_FILE:-}"
}

get_header_value() {
  local header_file="$1"
  local key="$2"
  awk -v k="$(echo "$key" | tr '[:upper:]' '[:lower:]')" '
    BEGIN{IGNORECASE=1}
    {
      split($0, parts, ":")
      name=tolower(parts[1])
      if (name==k) {
        sub(/^[^:]+:[[:space:]]*/, "", $0)
        gsub(/\r$/, "", $0)
        value=$0
      }
    }
    END{print value}
  ' "$header_file"
}

echo "BASE_URL=$BASE_URL"
echo "RUN_ID=$RUN_ID"

echo
echo "=== HEALTH /api/healthz ==="
request_json "GET" "$BASE_URL/api/healthz" "" "" "" "" "200"
HEALTH_OK="$(json_field "$RESPONSE_BODY_FILE" "ok")"
HEALTH_DB_OK="$(json_field "$RESPONSE_BODY_FILE" "db_ok")"
assert_true "$([[ "$HEALTH_OK" == "true" ]] && echo 1 || echo 0)" "/api/healthz did not return ok=true"
assert_true "$([[ "$HEALTH_DB_OK" == "true" ]] && echo 1 || echo 0)" "/api/healthz did not return db_ok=true"
echo "status=$RESPONSE_STATUS ok=$HEALTH_OK db_ok=$HEALTH_DB_OK"
cleanup_response_files

echo
echo "=== HEALTH /health ==="
request_json "GET" "$BASE_URL/health" "" "" "" "" "200"
HEALTH_OK="$(json_field "$RESPONSE_BODY_FILE" "ok")"
HEALTH_DB_OK="$(json_field "$RESPONSE_BODY_FILE" "db_ok")"
assert_true "$([[ "$HEALTH_OK" == "true" ]] && echo 1 || echo 0)" "/health did not return ok=true"
assert_true "$([[ "$HEALTH_DB_OK" == "true" ]] && echo 1 || echo 0)" "/health did not return db_ok=true"
echo "status=$RESPONSE_STATUS ok=$HEALTH_OK db_ok=$HEALTH_DB_OK"
cleanup_response_files

echo
echo "=== RIDER REGISTER + IDEMPOTENCY REPLAY ==="
REGISTER_KEY="$(idem rider-register)"
REGISTER_BODY="{\"email\":\"$RIDER_EMAIL\",\"password\":\"$PASSWORD\",\"role\":\"rider\",\"display_name\":\"Smoke Rider\",\"next_of_kin\":{\"full_name\":\"Smoke NOK\",\"phone\":\"+2348010000000\",\"relationship\":\"Sibling\"}}"
request_json "POST" "$BASE_URL/auth/register" "$REGISTER_BODY" "" "$REGISTER_KEY"
FIRST_REGISTER_BODY_FILE="$RESPONSE_BODY_FILE"
FIRST_REGISTER_STATUS="$RESPONSE_STATUS"
FIRST_REGISTER_RESULT_HASH="$(json_field "$FIRST_REGISTER_BODY_FILE" "result_hash")"
FIRST_REGISTER_USER_ID="$(json_field "$FIRST_REGISTER_BODY_FILE" "user_id")"
request_json "POST" "$BASE_URL/auth/register" "$REGISTER_BODY" "" "$REGISTER_KEY"
REPLAY_STATUS="$RESPONSE_STATUS"
REPLAY_FLAG="$(json_field "$RESPONSE_BODY_FILE" "replayed")"
REPLAY_RESULT_HASH="$(json_field "$RESPONSE_BODY_FILE" "result_hash")"
if [[ "$REPLAY_FLAG" != "true" && ( -z "$FIRST_REGISTER_RESULT_HASH" || "$FIRST_REGISTER_RESULT_HASH" != "$REPLAY_RESULT_HASH" ) ]]; then
  echo "Register replay did not expose replayed=true or matching result_hash"
  echo "first_result_hash=$FIRST_REGISTER_RESULT_HASH replay_result_hash=$REPLAY_RESULT_HASH replayed=$REPLAY_FLAG"
  cat "$RESPONSE_BODY_FILE"
  exit 1
fi
echo "first_status=$FIRST_REGISTER_STATUS replay_status=$REPLAY_STATUS rider_user_id=$FIRST_REGISTER_USER_ID replayed=$REPLAY_FLAG"
cleanup_response_files
rm -f "$FIRST_REGISTER_BODY_FILE"

echo
echo "=== RIDER LOGIN + TRACE PROPAGATION ==="
TRACE_ID="smoke-${RUN_ID}-trace-login"
LOGIN_BODY="{\"email\":\"$RIDER_EMAIL\",\"password\":\"$PASSWORD\"}"
request_json "POST" "$BASE_URL/auth/login" "$LOGIN_BODY" "" "" "$TRACE_ID" "200"
RIDER_TOKEN="$(json_field "$RESPONSE_BODY_FILE" "token")"
TRACE_HEADER_VALUE="$(get_header_value "$RESPONSE_HEADER_FILE" "x-trace-id")"
TRACE_BODY_VALUE="$(json_field "$RESPONSE_BODY_FILE" "trace_id")"
if [[ "$TRACE_HEADER_VALUE" != "$TRACE_ID" && "$TRACE_BODY_VALUE" != "$TRACE_ID" ]]; then
  echo "Trace id propagation failed. header='$TRACE_HEADER_VALUE' body='$TRACE_BODY_VALUE' expected='$TRACE_ID'"
  exit 1
fi
if [[ -z "$RIDER_TOKEN" ]]; then
  echo "Missing rider token in login response"
  cat "$RESPONSE_BODY_FILE"
  exit 1
fi
echo "status=$RESPONSE_STATUS rider_email=$RIDER_EMAIL trace=$TRACE_HEADER_VALUE"
cleanup_response_files

echo
echo "=== RIDER REQUEST RIDE ==="
RIDE_BODY="{\"scheduled_departure_at\":\"$NOW_UTC\",\"trip_scope\":\"intra_city\",\"distance_meters\":12000,\"duration_seconds\":1800,\"luggage_count\":1,\"vehicle_class\":\"sedan\",\"base_fare_minor\":100000,\"premium_markup_minor\":5000,\"connection_fee_minor\":5000}"
request_json "POST" "$BASE_URL/rides/request" "$RIDE_BODY" "$RIDER_TOKEN" "$(idem ride-request)"
RIDE_ID="$(json_field "$RESPONSE_BODY_FILE" "ride_id")"
if [[ -z "$RIDE_ID" ]]; then
  echo "Missing ride_id from request ride response"
  cat "$RESPONSE_BODY_FILE"
  exit 1
fi
echo "status=$RESPONSE_STATUS ride_id=$RIDE_ID"
cleanup_response_files

echo
echo "=== DRIVER REGISTER + LOGIN ==="
DRIVER_REGISTER_BODY="{\"email\":\"$DRIVER_EMAIL\",\"password\":\"$PASSWORD\",\"role\":\"driver\",\"display_name\":\"Smoke Driver\"}"
request_json "POST" "$BASE_URL/auth/register" "$DRIVER_REGISTER_BODY" "" "$(idem driver-register)"
DRIVER_USER_ID="$(json_field "$RESPONSE_BODY_FILE" "user_id")"
cleanup_response_files
DRIVER_LOGIN_BODY="{\"email\":\"$DRIVER_EMAIL\",\"password\":\"$PASSWORD\"}"
request_json "POST" "$BASE_URL/auth/login" "$DRIVER_LOGIN_BODY" "" "" "" "200"
DRIVER_TOKEN="$(json_field "$RESPONSE_BODY_FILE" "token")"
if [[ -z "$DRIVER_TOKEN" ]]; then
  echo "Missing driver token in login response"
  cat "$RESPONSE_BODY_FILE"
  exit 1
fi
echo "driver_user_id=$DRIVER_USER_ID login_status=$RESPONSE_STATUS"
cleanup_response_files

echo
echo "=== DRIVER ACCEPT RIDE + REPLAY ==="
ACCEPT_KEY="$(idem ride-accept)"
request_json "POST" "$BASE_URL/rides/$RIDE_ID/accept" "{}" "$DRIVER_TOKEN" "$ACCEPT_KEY" "" "200"
FIRST_ACCEPT_STATUS="$RESPONSE_STATUS"
cleanup_response_files
request_json "POST" "$BASE_URL/rides/$RIDE_ID/accept" "{}" "$DRIVER_TOKEN" "$ACCEPT_KEY" "" "200"
echo "accept_status=$FIRST_ACCEPT_STATUS accept_replay_status=$RESPONSE_STATUS"
cleanup_response_files

if [[ -n "$ADMIN_EMAIL" && -n "$ADMIN_PASSWORD" ]]; then
  echo
  echo "=== ADMIN LOGIN ==="
  ADMIN_LOGIN_BODY="{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}"
  request_json "POST" "$BASE_URL/auth/login" "$ADMIN_LOGIN_BODY" "" "" "" "200"
  ADMIN_TOKEN="$(json_field "$RESPONSE_BODY_FILE" "token")"
  if [[ -z "$ADMIN_TOKEN" ]]; then
    echo "Missing admin token in login response"
    cat "$RESPONSE_BODY_FILE"
    exit 1
  fi
  echo "admin_login_status=$RESPONSE_STATUS"
  cleanup_response_files

  echo
  echo "=== DISPUTE OPEN + RESOLVE ==="
  request_json "POST" "$BASE_URL/disputes" "{\"ride_id\":\"$RIDE_ID\",\"reason\":\"smoke_test\"}" "$ADMIN_TOKEN" "$(idem dispute-open)"
  DISPUTE_ID="$(json_field "$RESPONSE_BODY_FILE" "dispute_id")"
  echo "dispute_open_status=$RESPONSE_STATUS dispute_id=$DISPUTE_ID"
  cleanup_response_files
  if [[ -n "$DISPUTE_ID" ]]; then
    request_json "POST" "$BASE_URL/disputes/$DISPUTE_ID/resolve" "{\"refund_minor\":0,\"resolution_note\":\"smoke_resolve\"}" "$ADMIN_TOKEN" "$(idem dispute-resolve)" "" "200"
    echo "dispute_resolve_status=$RESPONSE_STATUS"
    cleanup_response_files
  fi

  if [[ -n "$REVERSAL_LEDGER_ID" ]]; then
    echo
    echo "=== ADMIN REVERSAL + REPLAY CHECK ==="
    REVERSAL_KEY="$(idem admin-reversal)"
    REVERSAL_BODY="{\"original_ledger_id\":$REVERSAL_LEDGER_ID,\"reason\":\"smoke_reversal\"}"
    request_json "POST" "$BASE_URL/admin/reversal" "$REVERSAL_BODY" "$ADMIN_TOKEN" "$REVERSAL_KEY" "" "200"
    REVERSAL_STATUS_1="$RESPONSE_STATUS"
    cleanup_response_files
    request_json "POST" "$BASE_URL/admin/reversal" "$REVERSAL_BODY" "$ADMIN_TOKEN" "$REVERSAL_KEY" "" "200"
    REVERSAL_STATUS_2="$RESPONSE_STATUS"
    echo "reversal_status_first=$REVERSAL_STATUS_1 reversal_status_replay=$REVERSAL_STATUS_2"
    cleanup_response_files
  else
    echo
    echo "=== ADMIN REVERSAL SKIPPED ==="
    echo "Set HAILO_REVERSAL_LEDGER_ID to run reversal replay smoke."
  fi
else
  echo
  echo "=== ADMIN FLOW SKIPPED ==="
  echo "Set HAILO_ADMIN_EMAIL and HAILO_ADMIN_PASSWORD to run admin smoke flow."
fi

echo
echo "Smoke suite completed successfully."
