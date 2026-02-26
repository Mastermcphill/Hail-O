#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACT_ROOT="${SCRIPT_DIR}/test_artifacts/e2e"
RUN_TS="$(date -u +%Y%m%d_%H%M%S)"
RUN_DIR="${ARTIFACT_ROOT}/${RUN_TS}"
STEPS_FILE="${RUN_DIR}/steps.ndjson"
FAILURES_FILE="${RUN_DIR}/failures.ndjson"
TRACE_IDS_FILE="${RUN_DIR}/trace_ids.ndjson"

BASE_URL="${BASE_URL:-}"
TARGET_ENV="${ENV:-staging}"
PHONE_E164="${E2E_PHONE_E164:-+15550001111}"
OTP_CODE="${E2E_OTP_CODE:-000000}"
ACCESS_TOKEN="${E2E_ACCESS_TOKEN:-}"
ADMIN_TOKEN_VALUE="${E2E_ADMIN_TOKEN:-${ADMIN_TOKEN:-}}"
WEBHOOK_SECRET_VALUE="${E2E_WEBHOOK_SECRET:-${PAYMENTS_WEBHOOK_SECRET:-}}"
PAYSTACK_SECRET_VALUE="${E2E_PAYSTACK_SECRET:-${PAYSTACK_WEBHOOK_SECRET:-${PAYSTACK_SECRET_KEY:-}}}"

usage() {
  cat <<'EOF'
Usage: smoke_e2e.sh --base=<url> [options]

Options:
  --base=<url>              Base URL, for example https://staging.example.com
  --env=<name>              Environment label (default: staging)
  --phone=<e164>            Phone number for OTP login (default: +15550001111)
  --otp-code=<code>         OTP code for staging/dev bypass (default: 000000)
  --token=<jwt>             Pre-provisioned access token (skips OTP)
  --admin-token=<token>     Admin token for admin flow endpoints
  --webhook-secret=<secret> PAYMENTS_WEBHOOK_SECRET for x-webhook-signature
  --paystack-secret=<key>   PAYSTACK secret for x-paystack-signature

Environment variable equivalents:
  BASE_URL, ENV, E2E_PHONE_E164, E2E_OTP_CODE, E2E_ACCESS_TOKEN,
  E2E_ADMIN_TOKEN/ADMIN_TOKEN, E2E_WEBHOOK_SECRET/PAYMENTS_WEBHOOK_SECRET,
  E2E_PAYSTACK_SECRET/PAYSTACK_WEBHOOK_SECRET/PAYSTACK_SECRET_KEY
EOF
}

for arg in "$@"; do
  case "$arg" in
    --base=*) BASE_URL="${arg#*=}" ;;
    --env=*) TARGET_ENV="${arg#*=}" ;;
    --phone=*) PHONE_E164="${arg#*=}" ;;
    --otp-code=*) OTP_CODE="${arg#*=}" ;;
    --token=*) ACCESS_TOKEN="${arg#*=}" ;;
    --admin-token=*) ADMIN_TOKEN_VALUE="${arg#*=}" ;;
    --webhook-secret=*) WEBHOOK_SECRET_VALUE="${arg#*=}" ;;
    --paystack-secret=*) PAYSTACK_SECRET_VALUE="${arg#*=}" ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: ${arg}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${BASE_URL}" ]]; then
  echo "BASE_URL is required (use --base=...)" >&2
  exit 2
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 2
  fi
}

require_cmd curl
require_cmd jq
require_cmd openssl

mkdir -p "${RUN_DIR}"
: >"${STEPS_FILE}"
: >"${FAILURES_FILE}"
: >"${TRACE_IDS_FILE}"

echo "[smoke] base=${BASE_URL} env=${TARGET_ENV}"
echo "[smoke] artifacts=${RUN_DIR}"

json_escape() {
  jq -Rn --arg value "$1" '$value'
}

now_ms() {
  local ms
  ms="$(date +%s%3N 2>/dev/null || true)"
  if [[ -n "${ms}" && "${ms}" =~ ^[0-9]+$ ]]; then
    echo "${ms}"
    return 0
  fi
  echo "$(( $(date +%s) * 1000 ))"
}

uuidish() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    printf '%s-%s-%s-%s\n' "$(date +%s)" "$RANDOM" "$RANDOM" "$RANDOM"
  fi
}

append_step() {
  local name="$1"
  local ok="$2"
  local status="$3"
  local duration_ms="$4"
  local trace_id="$5"
  local artifact="$6"
  local detail="$7"

  jq -n \
    --arg name "${name}" \
    --argjson ok "${ok}" \
    --arg status "${status}" \
    --argjson duration_ms "${duration_ms}" \
    --arg trace_id "${trace_id}" \
    --arg artifact "${artifact}" \
    --arg detail "${detail}" \
    '{name:$name,ok:$ok,status:$status,duration_ms:$duration_ms,trace_id:$trace_id,artifact:$artifact,detail:$detail}' \
    >>"${STEPS_FILE}"

  if [[ -n "${trace_id}" ]]; then
    jq -n --arg trace_id "${trace_id}" '{trace_id:$trace_id}' >>"${TRACE_IDS_FILE}"
  fi
  if [[ "${ok}" != "true" ]]; then
    jq -n \
      --arg name "${name}" \
      --arg status "${status}" \
      --arg trace_id "${trace_id}" \
      --arg detail "${detail}" \
      '{name:$name,status:$status,trace_id:$trace_id,detail:$detail}' \
      >>"${FAILURES_FILE}"
  fi
}

run_request() {
  local method="$1"
  local path="$2"
  local body="$3"
  local out_file="$4"
  shift 4

  local trace="smoke-$(uuidish)"
  local header_args=(
    -H "accept: application/json"
    -H "x-trace-id: ${trace}"
  )
  while (($# > 0)); do
    header_args+=( -H "$1" )
    shift
  done

  local response_code
  if [[ -n "${body}" ]]; then
    response_code="$(curl -sS -o "${out_file}" -w "%{http_code}" -X "${method}" "${BASE_URL}${path}" "${header_args[@]}" -H "content-type: application/json" --data "${body}")"
  else
    response_code="$(curl -sS -o "${out_file}" -w "%{http_code}" -X "${method}" "${BASE_URL}${path}" "${header_args[@]}")"
  fi
  echo "${response_code}"
}

assert_step() {
  local step_name="$1"
  local expected_codes="$2"
  local code="$3"
  local start_ms="$4"
  local artifact_file="$5"
  local detail="${6:-}"

  local end_ms duration_ms trace_id ok
  end_ms="$(now_ms)"
  duration_ms="$(( end_ms - start_ms ))"
  trace_id="$(jq -r '.trace_id // empty' "${artifact_file}" 2>/dev/null || true)"
  ok="false"
  if [[ " ${expected_codes} " == *" ${code} "* ]]; then
    ok="true"
  fi
  append_step "${step_name}" "${ok}" "${code}" "${duration_ms}" "${trace_id}" "$(basename "${artifact_file}")" "${detail}"
  if [[ "${ok}" != "true" ]]; then
    return 1
  fi
  return 0
}

extract_json_value() {
  local file="$1"
  local jq_expr="$2"
  jq -er "${jq_expr}" "${file}" 2>/dev/null || true
}

safe_copy_json() {
  local src="$1"
  local target_name="$2"
  cp "${src}" "${RUN_DIR}/${target_name}"
}

tmp_file() {
  mktemp "${RUN_DIR}/tmp.XXXXXX.json"
}

fail_fast="false"

run_step_request() {
  local step_name="$1"
  local expected_codes="$2"
  local method="$3"
  local path="$4"
  local body="$5"
  local artifact_name="$6"
  shift 6

  local start_ms out_file code
  start_ms="$(now_ms)"
  out_file="$(tmp_file)"
  code="$(run_request "${method}" "${path}" "${body}" "${out_file}" "$@")"
  safe_copy_json "${out_file}" "${artifact_name}"
  if ! assert_step "${step_name}" "${expected_codes}" "${code}" "${start_ms}" "${RUN_DIR}/${artifact_name}"; then
    fail_fast="true"
    return 1
  fi
  return 0
}

auth_header() {
  if [[ -n "${ACCESS_TOKEN}" ]]; then
    echo "authorization: Bearer ${ACCESS_TOKEN}"
  fi
}

# FLOW A: Auth + marketplace purchase + payment intent + webhook + purchase verify
if [[ -z "${ACCESS_TOKEN}" ]]; then
  run_id="$(date -u +%s)"
  request_body="$(jq -n --arg phone "${PHONE_E164}" '{phone_e164:$phone}')"
  run_step_request "auth.otp_request" "200" "POST" "/auth/otp/request" "${request_body}" "01_auth_otp_request.json" || true

  if [[ "${fail_fast}" == "false" ]]; then
    verify_body="$(jq -n --arg phone "${PHONE_E164}" --arg code "${OTP_CODE}" '{phone_e164:$phone,code:$code}')"
    run_step_request "auth.otp_verify" "200" "POST" "/auth/otp/verify" "${verify_body}" "02_auth_otp_verify.json" || true
    if [[ "${fail_fast}" == "false" ]]; then
      ACCESS_TOKEN="$(extract_json_value "${RUN_DIR}/02_auth_otp_verify.json" '.access_token // .data.access_token // empty')"
      REFRESH_TOKEN="$(extract_json_value "${RUN_DIR}/02_auth_otp_verify.json" '.refresh_token // .data.refresh_token // empty')"
      if [[ -z "${ACCESS_TOKEN}" ]]; then
        append_step "auth.extract_token" false "parse_error" 0 "" "02_auth_otp_verify.json" "access_token missing"
        fail_fast="true"
      else
        append_step "auth.extract_token" true "ok" 0 "" "02_auth_otp_verify.json" "token acquired"
      fi
      if [[ -n "${REFRESH_TOKEN:-}" ]]; then
        refresh_body="$(jq -n --arg token "${REFRESH_TOKEN}" '{refresh_token:$token}')"
        run_step_request "auth.refresh" "200" "POST" "/auth/token/refresh" "${refresh_body}" "03_auth_refresh.json" "authorization: Bearer ${ACCESS_TOKEN}" || true
      fi
    fi
  fi
else
  append_step "auth.preprovisioned_token" true "ok" 0 "" "" "using provided E2E_ACCESS_TOKEN"
fi

OFFER_ID=""
PURCHASE_ID=""
INTENT_ID=""
TRIP_ID=""
DRIVER_ID=""

if [[ "${fail_fast}" == "false" ]]; then
  run_step_request "marketplace.offers" "200" "GET" "/marketplace/offers" "" "04_marketplace_offers.json" "authorization: Bearer ${ACCESS_TOKEN}" || true
  OFFER_ID="$(extract_json_value "${RUN_DIR}/04_marketplace_offers.json" '.data[0].id // .offers[0].id // empty')"
  if [[ -z "${OFFER_ID}" ]]; then
    append_step "marketplace.pick_offer" false "parse_error" 0 "" "04_marketplace_offers.json" "no offer id found"
    fail_fast="true"
  else
    append_step "marketplace.pick_offer" true "ok" 0 "" "04_marketplace_offers.json" "offer_id=${OFFER_ID}"
  fi
fi

if [[ "${fail_fast}" == "false" ]]; then
  purchase_idem="smoke-purchase-$(uuidish)"
  purchase_body="$(jq -n --arg offer_id "${OFFER_ID}" '{offer_id:$offer_id,quantity:1}')"
  run_step_request "marketplace.purchase_create" "200 201" "POST" "/marketplace/purchases" "${purchase_body}" "05_marketplace_purchase_create.json" "authorization: Bearer ${ACCESS_TOKEN}" "idempotency-key: ${purchase_idem}" || true
  PURCHASE_ID="$(extract_json_value "${RUN_DIR}/05_marketplace_purchase_create.json" '.data.purchase.purchase_id // .data.purchase.purchaseId // .data.purchase_id // .data.purchaseId // .purchase.purchase_id // .purchase_id // empty')"
  if [[ -z "${PURCHASE_ID}" ]]; then
    append_step "marketplace.extract_purchase_id" false "parse_error" 0 "" "05_marketplace_purchase_create.json" "purchase id missing"
    fail_fast="true"
  else
    append_step "marketplace.extract_purchase_id" true "ok" 0 "" "05_marketplace_purchase_create.json" "purchase_id=${PURCHASE_ID}"
  fi
fi

if [[ "${fail_fast}" == "false" ]]; then
  intent_body="$(jq -n --arg purchase_id "${PURCHASE_ID}" '{purchase_id:$purchase_id}')"
  intent_idem="smoke-intent-$(uuidish)"
  run_step_request "payments.intent_create" "200" "POST" "/payments/intents" "${intent_body}" "06_payments_intent_create.json" "authorization: Bearer ${ACCESS_TOKEN}" "idempotency-key: ${intent_idem}" || true
  INTENT_ID="$(extract_json_value "${RUN_DIR}/06_payments_intent_create.json" '.data.id // .id // empty')"
  if [[ -n "${INTENT_ID}" ]]; then
    append_step "payments.extract_intent_id" true "ok" 0 "" "06_payments_intent_create.json" "intent_id=${INTENT_ID}"
  else
    append_step "payments.extract_intent_id" false "parse_error" 0 "" "06_payments_intent_create.json" "intent id missing"
    fail_fast="true"
  fi
fi

if [[ "${fail_fast}" == "false" ]]; then
  provider_event_id="evt-smoke-$(uuidish)"
  webhook_payload="$(jq -n --arg event_id "${provider_event_id}" --arg purchase_id "${PURCHASE_ID}" '{provider_event_id:$event_id,event_type:"payment_succeeded",purchase_id:$purchase_id,event:"charge.success",data:{id:$event_id,metadata:{purchase_id:$purchase_id}}}')"
  webhook_headers=("authorization: Bearer ${ACCESS_TOKEN}")

  if [[ -n "${WEBHOOK_SECRET_VALUE}" ]]; then
    webhook_sig="$(printf '%s' "${webhook_payload}" | openssl dgst -sha256 -hmac "${WEBHOOK_SECRET_VALUE}" -hex | awk '{print $NF}')"
    webhook_headers+=("x-webhook-signature: ${webhook_sig}")
  fi
  if [[ -n "${PAYSTACK_SECRET_VALUE}" ]]; then
    paystack_sig="$(printf '%s' "${webhook_payload}" | openssl dgst -sha512 -hmac "${PAYSTACK_SECRET_VALUE}" -hex | awk '{print $NF}')"
    webhook_headers+=("x-paystack-signature: ${paystack_sig}")
    webhook_headers+=("x-paystack-event-id: ${provider_event_id}")
  fi

  run_step_request "payments.webhook_simulate" "200" "POST" "/webhooks/payments" "${webhook_payload}" "07_payments_webhook.json" "${webhook_headers[@]}" || true
fi

if [[ "${fail_fast}" == "false" ]]; then
  run_step_request "marketplace.purchase_get" "200" "GET" "/marketplace/purchases/${PURCHASE_ID}" "" "08_marketplace_purchase_get.json" "authorization: Bearer ${ACCESS_TOKEN}" || true
  purchase_status="$(extract_json_value "${RUN_DIR}/08_marketplace_purchase_get.json" '.data.status // .data.purchase.status // .status // .purchase.status // empty' | tr '[:upper:]' '[:lower:]')"
  if [[ "${purchase_status}" == "paid" || "${purchase_status}" == "active" || "${purchase_status}" == "pending_payment" ]]; then
    append_step "marketplace.purchase_status" true "ok" 0 "" "08_marketplace_purchase_get.json" "status=${purchase_status}"
  else
    append_step "marketplace.purchase_status" false "unexpected_status" 0 "" "08_marketplace_purchase_get.json" "status=${purchase_status:-missing}"
    fail_fast="true"
  fi
fi

# FLOW D: Dispatch
if [[ "${fail_fast}" == "false" ]]; then
  quote_body='{"pickup":{"lat":6.455,"lng":3.384},"dropoff":{"lat":6.6018,"lng":3.3515},"service_level":"standard"}'
  run_step_request "dispatch.quote" "200" "POST" "/dispatch/quote" "${quote_body}" "09_dispatch_quote.json" "authorization: Bearer ${ACCESS_TOKEN}" || true
  if [[ "${fail_fast}" == "false" ]]; then
    quote_price="$(extract_json_value "${RUN_DIR}/09_dispatch_quote.json" '.price_minor // empty')"
    if [[ -z "${quote_price}" ]]; then
      append_step "dispatch.quote_fields" false "parse_error" 0 "" "09_dispatch_quote.json" "missing price_minor"
      fail_fast="true"
    else
      append_step "dispatch.quote_fields" true "ok" 0 "" "09_dispatch_quote.json" "price_minor=${quote_price}"
    fi
  fi
fi

if [[ "${fail_fast}" == "false" ]]; then
  trip_body='{"pickup":{"lat":6.455,"lng":3.384,"address":"Lagos Island"},"dropoff":{"lat":6.6018,"lng":3.3515,"address":"Ikeja"},"notes":"smoke run"}'
  run_step_request "dispatch.trip_create" "201" "POST" "/dispatch/trips" "${trip_body}" "10_dispatch_trip_create.json" "authorization: Bearer ${ACCESS_TOKEN}" || true
  TRIP_ID="$(extract_json_value "${RUN_DIR}/10_dispatch_trip_create.json" '.trip.id // .data.trip.id // empty')"
  if [[ -z "${TRIP_ID}" ]]; then
    append_step "dispatch.extract_trip_id" false "parse_error" 0 "" "10_dispatch_trip_create.json" "trip id missing"
    fail_fast="true"
  else
    append_step "dispatch.extract_trip_id" true "ok" 0 "" "10_dispatch_trip_create.json" "trip_id=${TRIP_ID}"
  fi
fi

if [[ "${fail_fast}" == "false" ]]; then
  run_step_request "dispatch.status_searching" "200" "POST" "/dispatch/trips/${TRIP_ID}/status" '{"status":"searching"}' "11_dispatch_status_searching.json" "authorization: Bearer ${ACCESS_TOKEN}" || true
fi

if [[ "${fail_fast}" == "false" ]]; then
  # provision a driver account via existing auth credentials endpoints.
  driver_run_id="$(date -u +%s)"
  driver_email="smoke.driver.${driver_run_id}@hailo.dev"
  driver_password="Passw0rd!"
  register_driver_body="$(jq -n --arg email "${driver_email}" --arg pass "${driver_password}" '{email:$email,password:$pass,role:"driver",display_name:"Smoke Driver"}')"
  run_step_request "dispatch.driver_register" "201" "POST" "/auth/register" "${register_driver_body}" "12_dispatch_driver_register.json" "idempotency-key: smoke-driver-${driver_run_id}" || true
  if [[ "${fail_fast}" == "false" ]]; then
    login_driver_body="$(jq -n --arg email "${driver_email}" --arg pass "${driver_password}" '{email:$email,password:$pass}')"
    run_step_request "dispatch.driver_login" "200" "POST" "/auth/login" "${login_driver_body}" "13_dispatch_driver_login.json" || true
    DRIVER_ID="$(extract_json_value "${RUN_DIR}/13_dispatch_driver_login.json" '.user_id // .data.user_id // empty')"
    if [[ -z "${DRIVER_ID}" ]]; then
      append_step "dispatch.extract_driver_id" false "parse_error" 0 "" "13_dispatch_driver_login.json" "driver user_id missing"
      fail_fast="true"
    else
      append_step "dispatch.extract_driver_id" true "ok" 0 "" "13_dispatch_driver_login.json" "driver_id=${DRIVER_ID}"
    fi
  fi
fi

if [[ "${fail_fast}" == "false" ]]; then
  assign_body="$(jq -n --arg driver_id "${DRIVER_ID}" '{driver_id:$driver_id}')"
  run_step_request "dispatch.assign" "200" "POST" "/dispatch/trips/${TRIP_ID}/assign" "${assign_body}" "14_dispatch_assign.json" "authorization: Bearer ${ACCESS_TOKEN}" || true
fi

if [[ "${fail_fast}" == "false" ]]; then
  run_step_request "dispatch.status_enroute_pickup" "200" "POST" "/dispatch/trips/${TRIP_ID}/status" '{"status":"enroute_pickup"}' "15_dispatch_status_enroute_pickup.json" "authorization: Bearer ${ACCESS_TOKEN}" || true
fi
if [[ "${fail_fast}" == "false" ]]; then
  run_step_request "dispatch.status_picked_up" "200" "POST" "/dispatch/trips/${TRIP_ID}/status" '{"status":"picked_up"}' "16_dispatch_status_picked_up.json" "authorization: Bearer ${ACCESS_TOKEN}" || true
fi
if [[ "${fail_fast}" == "false" ]]; then
  run_step_request "dispatch.status_enroute_dropoff" "200" "POST" "/dispatch/trips/${TRIP_ID}/status" '{"status":"enroute_dropoff"}' "17_dispatch_status_enroute_dropoff.json" "authorization: Bearer ${ACCESS_TOKEN}" || true
fi
if [[ "${fail_fast}" == "false" ]]; then
  run_step_request "dispatch.status_delivered" "200" "POST" "/dispatch/trips/${TRIP_ID}/status" '{"status":"delivered"}' "18_dispatch_status_delivered.json" "authorization: Bearer ${ACCESS_TOKEN}" || true
fi
if [[ "${fail_fast}" == "false" ]]; then
  run_step_request "dispatch.trip_get" "200" "GET" "/dispatch/trips/${TRIP_ID}" "" "19_dispatch_trip_get.json" "authorization: Bearer ${ACCESS_TOKEN}" || true
  delivered_status="$(extract_json_value "${RUN_DIR}/19_dispatch_trip_get.json" '.trip.status // .data.trip.status // empty' | tr '[:upper:]' '[:lower:]')"
  if [[ "${delivered_status}" == "delivered" ]]; then
    append_step "dispatch.delivered_assert" true "ok" 0 "" "19_dispatch_trip_get.json" "status=delivered"
  else
    append_step "dispatch.delivered_assert" false "unexpected_status" 0 "" "19_dispatch_trip_get.json" "status=${delivered_status:-missing}"
    fail_fast="true"
  fi
fi

# FLOW E: Admin
if [[ -n "${ADMIN_TOKEN_VALUE}" ]]; then
  if [[ "${fail_fast}" == "false" ]]; then
    run_step_request "admin.metrics" "200" "GET" "/admin/metrics?limit=5" "" "20_admin_metrics.json" "x-admin-token: ${ADMIN_TOKEN_VALUE}" || true
  fi
  if [[ "${fail_fast}" == "false" ]]; then
    run_step_request "admin.users" "200" "GET" "/admin/users?limit=5" "" "21_admin_users.json" "x-admin-token: ${ADMIN_TOKEN_VALUE}" || true
  fi
  if [[ "${fail_fast}" == "false" ]]; then
    run_step_request "admin.trips" "200" "GET" "/admin/trips?limit=5" "" "22_admin_trips.json" "x-admin-token: ${ADMIN_TOKEN_VALUE}" || true
  fi
else
  append_step "admin.skipped" true "skipped" 0 "" "" "ADMIN_TOKEN not provided"
fi

steps_json="$(jq -s '.' "${STEPS_FILE}")"
failures_json="$(jq -s '.' "${FAILURES_FILE}")"
trace_ids_json="$(jq -s 'map(.trace_id) | map(select(. != "")) | unique' "${TRACE_IDS_FILE}")"
overall_ok="true"
if [[ "${fail_fast}" == "true" ]]; then
  overall_ok="false"
fi

total_duration_ms="$(jq -s '[.[] | (.duration_ms // 0)] | add // 0' "${STEPS_FILE}")"

jq -n \
  --argjson ok "${overall_ok}" \
  --arg base_url "${BASE_URL}" \
  --arg env "${TARGET_ENV}" \
  --arg run_dir "${RUN_DIR}" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson total_duration_ms "${total_duration_ms}" \
  --argjson steps "${steps_json}" \
  --argjson failures "${failures_json}" \
  --argjson trace_ids "${trace_ids_json}" \
  '{ok:$ok,base_url:$base_url,env:$env,generated_at:$generated_at,total_duration_ms:$total_duration_ms,steps:$steps,failures:$failures,trace_ids:$trace_ids,artifact_dir:$run_dir}' \
  >"${RUN_DIR}/summary.json"

if [[ "${overall_ok}" == "true" ]]; then
  echo "PASS: smoke e2e completed"
  echo "summary: ${RUN_DIR}/summary.json"
  exit 0
fi

echo "FAIL: smoke e2e encountered failures"
echo "summary: ${RUN_DIR}/summary.json"
exit 1