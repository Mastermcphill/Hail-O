#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACT_ROOT="${SCRIPT_DIR}/test_artifacts/e2e"
RUN_TS="$(date -u +%Y%m%d_%H%M%S)"
RUN_DIR="${ARTIFACT_ROOT}/${RUN_TS}"
STEPS_FILE="${RUN_DIR}/steps.ndjson"
FAILURES_FILE="${RUN_DIR}/failures.ndjson"

DEFAULT_BASE_URL="https://hail-o-api-staging.onrender.com"
BASE_URL="${BASE_URL:-${DEFAULT_BASE_URL}}"
TARGET_ENV="${ENV:-staging}"
SMOKE_PHONE_VALUE="${SMOKE_PHONE_E164:-${TEST_PHONE_E164:-${E2E_PHONE_E164:-}}}"
SMOKE_OTP_VALUE="${SMOKE_OTP_CODE:-${TEST_OTP:-${E2E_OTP_CODE:-}}}"
SMOKE_WEBHOOK_SIM_VALUE="${SMOKE_WEBHOOK_SIM:-}"
ACCESS_TOKEN="${SMOKE_ACCESS_TOKEN:-${TEST_ACCESS_TOKEN:-${E2E_ACCESS_TOKEN:-}}}"
WEBHOOK_SECRET_VALUE="${PAYMENTS_WEBHOOK_SECRET:-${E2E_WEBHOOK_SECRET:-}}"
PAYSTACK_WEBHOOK_SECRET_VALUE="${PAYSTACK_WEBHOOK_SECRET:-${E2E_PAYSTACK_SECRET:-}}"
SMOKE_DRIVER_ID_VALUE="${SMOKE_DRIVER_ID:-${TEST_DRIVER_ID:-}}"
DRY_RUN="false"

usage() {
  cat <<'EOF'
Usage: smoke_e2e.sh --base=<url> [options]

Options:
  --base=<url>                    Target API base URL (default: https://hail-o-api-staging.onrender.com)
  --env=<name>                    Environment label (default: staging)
  --smoke-access-token=<jwt>      Pre-provisioned user access token
  --smoke-phone=<e164>            OTP phone (fallback flow)
  --smoke-otp=<code>              OTP code (fallback flow)
  --smoke-webhook-sim=<bool>      Simulate payment webhook (default: true in staging)
  --smoke-driver-id=<uuid>        Optional pre-seeded driver id for dispatch assign
  --webhook-secret=<secret>       Generic webhook secret for x-webhook-signature
  --paystack-webhook-secret=<s>   Paystack webhook secret for x-paystack-signature
  --dry-run                       Run without real HTTP calls (CI utility)

Environment variable fallbacks:
  BASE_URL, ENV,
  SMOKE_ACCESS_TOKEN|TEST_ACCESS_TOKEN|E2E_ACCESS_TOKEN,
  SMOKE_PHONE_E164|TEST_PHONE_E164|E2E_PHONE_E164,
  SMOKE_OTP_CODE|TEST_OTP|E2E_OTP_CODE,
  SMOKE_WEBHOOK_SIM,
  PAYMENTS_WEBHOOK_SECRET|E2E_WEBHOOK_SECRET,
  PAYSTACK_WEBHOOK_SECRET|E2E_PAYSTACK_SECRET|PAYSTACK_SECRET_KEY,
  SMOKE_DRIVER_ID|TEST_DRIVER_ID
EOF
}

normalize_bool() {
  local value="${1:-}"
  value="$(echo "$value" | tr '[:upper:]' '[:lower:]' | xargs)"
  case "$value" in
    1|true|yes|y|on) echo "true" ;;
    *) echo "false" ;;
  esac
}

for arg in "$@"; do
  case "$arg" in
    --base=*) BASE_URL="${arg#*=}" ;;
    --env=*) TARGET_ENV="${arg#*=}" ;;
    --smoke-access-token=*) ACCESS_TOKEN="${arg#*=}" ;;
    --smoke-phone=*) SMOKE_PHONE_VALUE="${arg#*=}" ;;
    --smoke-otp=*) SMOKE_OTP_VALUE="${arg#*=}" ;;
    --smoke-webhook-sim=*) SMOKE_WEBHOOK_SIM_VALUE="${arg#*=}" ;;
    --admin-token=*|--admin-token-enabled=*|--smoke-mint-path=*)
      # Deprecated no-op args kept for backward compatibility.
      ;;
    --access-token=*) ACCESS_TOKEN="${arg#*=}" ;;
    --test-phone=*) SMOKE_PHONE_VALUE="${arg#*=}" ;;
    --test-otp=*) SMOKE_OTP_VALUE="${arg#*=}" ;;
    --payments-test-mode=*) SMOKE_WEBHOOK_SIM_VALUE="${arg#*=}" ;;
    --webhook-secret=*) WEBHOOK_SECRET_VALUE="${arg#*=}" ;;
    --paystack-webhook-secret=*) PAYSTACK_WEBHOOK_SECRET_VALUE="${arg#*=}" ;;
    --smoke-driver-id=*) SMOKE_DRIVER_ID_VALUE="${arg#*=}" ;;
    --test-driver-id=*) SMOKE_DRIVER_ID_VALUE="${arg#*=}" ;;
    --dry-run) DRY_RUN="true" ;;
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

BASE_URL="${BASE_URL%/}"
TARGET_ENV="$(echo "$TARGET_ENV" | tr '[:upper:]' '[:lower:]' | xargs)"
if [[ -z "${SMOKE_WEBHOOK_SIM_VALUE// }" ]]; then
  case "$TARGET_ENV" in
    staging|stage|development|dev|test) SMOKE_WEBHOOK_SIM_VALUE="true" ;;
    *) SMOKE_WEBHOOK_SIM_VALUE="false" ;;
  esac
fi
SMOKE_WEBHOOK_SIM_VALUE="$(normalize_bool "$SMOKE_WEBHOOK_SIM_VALUE")"
if [[ "$DRY_RUN" == "true" && -z "${ACCESS_TOKEN// }" ]]; then
  ACCESS_TOKEN="dry_access_token"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 2
  fi
}

require_cmd jq
if [[ "$DRY_RUN" != "true" ]]; then
  require_cmd curl
  require_cmd openssl
fi

mkdir -p "${RUN_DIR}"
: >"${STEPS_FILE}"
: >"${FAILURES_FILE}"

echo "[smoke] base=${BASE_URL} env=${TARGET_ENV} dry_run=${DRY_RUN}"
echo "[smoke] artifacts=${RUN_DIR}"

now_ms() {
  local ms
  ms="$(date +%s%3N 2>/dev/null || true)"
  if [[ -n "$ms" && "$ms" =~ ^[0-9]+$ ]]; then
    echo "$ms"
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

CALL_JSON='{}'

build_dry_run_response() {
  local method="$1"
  local path="$2"
  local body="$3"

  case "$path" in
    /health)
      jq -n '{status:200,body:{ok:true,service:"hail-o-backend",env:"dry-run"}}'
      ;;
    /ready|/api/ready)
      jq -n '{status:200,body:{ok:true,ready:true,db:true,migrations_ok:true,payments_ready:true,otp_ready:true,redis_configured:false,redis_ready:false}}'
      ;;
    /auth/otp/request)
      jq -n '{status:200,body:{ok:true}}'
      ;;
    /auth/otp/verify)
      jq -n '{status:200,body:{access_token:"dry_access_token",refresh_token:"dry_refresh_token",user:{id:"dry-user",phone_e164:"+15550001111"}}}'
      ;;
    /auth/register)
      jq -n '{status:201,body:{ok:true,user_id:"00000000-0000-4000-8000-000000000111"}}'
      ;;
    /auth/login)
      jq -n '{status:200,body:{ok:true,token:"dry_driver_token",user_id:"00000000-0000-4000-8000-000000000111"}}'
      ;;
    /marketplace/offers*)
      jq -n '{status:200,body:{ok:true,data:[{id:"offer_dry_001",title:"Dry Offer"}]}}'
      ;;
    /marketplace/purchases)
      jq -n '{status:200,body:{ok:true,data:{purchase:{purchase_id:"11111111-1111-4111-8111-111111111111",status:"pending_payment"}}}}'
      ;;
    /payments/intents)
      jq -n '{status:200,body:{ok:true,data:{id:"22222222-2222-4222-8222-222222222222",status:"pending",provider:"manual"}}}'
      ;;
    /webhooks/payments)
      jq -n '{status:200,body:{ok:true,data:{action:"processed"}}}'
      ;;
    /marketplace/purchases/*)
      jq -n '{status:200,body:{ok:true,data:{status:"paid",purchase:{status:"paid"}}}}'
      ;;
    /dispatch/quote)
      jq -n '{status:200,body:{ok:true,distance_km:12.35,duration_min_est:30,price_minor:4500,currency:"NGN",breakdown:{base_fare_minor:1000,per_km_minor:200}}}'
      ;;
    /dispatch/trips)
      if [[ "$method" == "POST" ]]; then
        jq -n '{status:201,body:{ok:true,trip:{id:"33333333-3333-4333-8333-333333333333",status:"created"}}}'
      else
        jq -n '{status:404,body:{ok:false,error_code:"ROUTE_NOT_FOUND"}}'
      fi
      ;;
    /dispatch/trips/*/assign)
      jq -n '{status:200,body:{ok:true,trip:{id:"33333333-3333-4333-8333-333333333333",status:"assigned"},assignment:{driver_id:"00000000-0000-4000-8000-000000000111",status:"assigned"}}}'
      ;;
    /dispatch/trips/*/status)
      local desired_status="searching"
      if [[ -n "$body" ]]; then
        desired_status="$(jq -r '.status // "searching"' <<<"$body" 2>/dev/null || echo "searching")"
      fi
      jq -n --arg status "$desired_status" '{status:200,body:{ok:true,trip:{id:"33333333-3333-4333-8333-333333333333",status:$status},event:{to_status:$status}}}'
      ;;
    /dispatch/trips/*)
      jq -n '{status:200,body:{ok:true,trip:{id:"33333333-3333-4333-8333-333333333333",status:"delivered"}}}'
      ;;
    /admin/metrics)
      jq -n '{status:200,body:{ok:true,users_total:1,trips_total:1,purchases_total:1}}'
      ;;
    /admin/users*|/admin/trips*|/admin/audit*)
      jq -n '{status:200,body:{ok:true,data:[]}}'
      ;;
    /admin/smoke/mint_token)
      jq -n '{status:200,body:{ok:true,access_token:"dry_access_token",user:{id:"00000000-0000-4000-8000-000000000123",phone_e164:"+15550001111"}}}'
      ;;
    /admin/test/session/mint|/admin/test/access-token|/admin/auth/mint|/admin/session/mint|/admin/tokens/mint)
      jq -n '{status:404,body:{ok:false,error_code:"ROUTE_NOT_FOUND"}}'
      ;;
    *)
      jq -n '{status:404,body:{ok:false,error_code:"ROUTE_NOT_FOUND"}}'
      ;;
  esac
}

call_http() {
  local method="$1"
  local path="$2"
  local body="$3"
  shift 3

  local url="${BASE_URL}${path}"
  local trace="smoke-$(uuidish)"
  local start_ms end_ms duration_ms
  start_ms="$(now_ms)"

  if [[ "$DRY_RUN" == "true" ]]; then
    local dry_json dry_status dry_body
    dry_json="$(build_dry_run_response "$method" "$path" "$body")"
    dry_status="$(jq -r '.status // 0' <<<"$dry_json")"
    dry_body="$(jq -c '.body' <<<"$dry_json")"
    end_ms="$(now_ms)"
    duration_ms="$(( end_ms - start_ms ))"
    CALL_JSON="$(jq -n \
      --arg method "$method" \
      --arg path "$path" \
      --arg url "$url" \
      --arg trace_id "$trace" \
      --argjson status "$dry_status" \
      --argjson duration_ms "$duration_ms" \
      --argjson response "$dry_body" \
      '{method:$method,path:$path,url:$url,status:$status,duration_ms:$duration_ms,trace_id:$trace_id,response:$response,curl_error:null}')"
    return 0
  fi

  local body_file err_file status resp_json trace_id curl_error
  body_file="$(mktemp "${RUN_DIR}/http_body.XXXXXX")"
  err_file="$(mktemp "${RUN_DIR}/http_err.XXXXXX")"

  local cmd=(
    curl -sS -o "$body_file" -w "%{http_code}" -X "$method" "$url"
    -H "accept: application/json"
    -H "x-trace-id: ${trace}"
  )
  while (($# > 0)); do
    cmd+=( -H "$1" )
    shift
  done
  if [[ -n "$body" ]]; then
    cmd+=( -H "content-type: application/json" --data "$body" )
  fi

  if ! status="$("${cmd[@]}" 2>"$err_file")"; then
    status="000"
  fi
  status="$(echo "$status" | tr -cd '0-9')"
  if [[ -z "$status" ]]; then
    status="0"
  fi

  end_ms="$(now_ms)"
  duration_ms="$(( end_ms - start_ms ))"

  if jq -e . "$body_file" >/dev/null 2>&1; then
    resp_json="$(cat "$body_file")"
  else
    local raw_body
    raw_body="$(cat "$body_file" 2>/dev/null || true)"
    resp_json="$(jq -Rn --arg raw "$raw_body" '$raw')"
  fi

  curl_error="$(cat "$err_file" 2>/dev/null || true)"
  trace_id="$(jq -r '.trace_id // .data.trace_id // empty' "$body_file" 2>/dev/null || true)"
  if [[ -z "$trace_id" ]]; then
    trace_id="$trace"
  fi

  CALL_JSON="$(jq -n \
    --arg method "$method" \
    --arg path "$path" \
    --arg url "$url" \
    --arg trace_id "$trace_id" \
    --argjson status "$status" \
    --argjson duration_ms "$duration_ms" \
    --argjson response "$resp_json" \
    --arg curl_error "$curl_error" \
    '{method:$method,path:$path,url:$url,status:$status,duration_ms:$duration_ms,trace_id:$trace_id,response:$response,curl_error:(if $curl_error=="" then null else $curl_error end)}')"

  rm -f "$body_file" "$err_file"
}

OVERALL_OK="true"

append_step_summary() {
  local step_id="$1"
  local artifact="$2"
  local ok="$3"
  local status="$4"
  local note="$5"
  local duration_ms="$6"
  local trace_ids_json="$7"

  jq -n \
    --arg step "$step_id" \
    --arg artifact "$artifact" \
    --argjson ok "$ok" \
    --arg status "$status" \
    --arg note "$note" \
    --argjson duration_ms "$duration_ms" \
    --argjson trace_ids "$trace_ids_json" \
    '{step:$step,ok:$ok,status:$status,note:$note,duration_ms:$duration_ms,trace_ids:$trace_ids,artifact:$artifact}' \
    >>"$STEPS_FILE"

  if [[ "$ok" != "true" ]]; then
    OVERALL_OK="false"
    jq -n \
      --arg step "$step_id" \
      --arg status "$status" \
      --arg note "$note" \
      --arg artifact "$artifact" \
      '{step:$step,status:$status,note:$note,artifact:$artifact}' \
      >>"$FAILURES_FILE"
  fi
}

write_step() {
  local step_id="$1"
  local artifact="$2"
  local ok="$3"
  local status="$4"
  local note="$5"
  local duration_ms="$6"
  local trace_ids_json="$7"
  local payload_json="$8"

  local sanitized_payload
  sanitized_payload="$(sanitize_json "$payload_json")"
  printf '%s\n' "$sanitized_payload" >"${RUN_DIR}/${artifact}"
  append_step_summary "$step_id" "$artifact" "$ok" "$status" "$note" "$duration_ms" "$trace_ids_json"
}

json_bool() {
  if [[ "$1" == "true" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

sanitize_json() {
  local input_json="$1"
  jq '
    def redact:
      if type == "string" then
        if length <= 6 then (. + "…") else (.[0:6] + "…") end
      else
        .
      end;
    def sensitive:
      test("token|secret|authorization|password|signature");
    def scrub:
      if type == "object" then
        with_entries(
          if (.key | ascii_downcase | sensitive) then
            .value |= redact
          else
            .value |= scrub
          end
        )
      elif type == "array" then
        map(scrub)
      else
        .
      end;
    scrub
  ' <<<"$input_json"
}

redact_token() {
  local token="${1:-}"
  token="$(echo "$token" | xargs)"
  if [[ -z "$token" ]]; then
    echo ""
    return 0
  fi
  if [[ "${#token}" -le 6 ]]; then
    echo "${token}…"
    return 0
  fi
  echo "${token:0:6}…"
}
# Step 01: Health
call_http "GET" "/health" ""
step01_call="$CALL_JSON"
step01_status="$(jq -r '.status' <<<"$step01_call")"
step01_body_ok="$(jq -r 'if (.response|type)=="object" then (.response.ok // false) else false end' <<<"$step01_call")"
step01_ok="false"
step01_note="Expected HTTP 200 and ok=true"
if [[ "$step01_status" == "200" && "$step01_body_ok" == "true" ]]; then
  step01_ok="true"
  step01_note="Health responded with ok=true"
fi
step01_payload="$(jq -n --argjson call "$step01_call" --arg expected "status=200 and ok=true" '{call:$call,expected:$expected}')"
step01_duration="$(jq -r '.duration_ms // 0' <<<"$step01_call")"
step01_traces="$(jq -c '[.trace_id // empty] | map(select(length>0))' <<<"$step01_call")"
write_step "01_health" "01_health.json" "$step01_ok" "$step01_status" "$step01_note" "$step01_duration" "$step01_traces" "$step01_payload"

# Step 02: Ready
call_http "GET" "/ready" ""
step02_call="$CALL_JSON"
step02_status="$(jq -r '.status' <<<"$step02_call")"
if [[ "$step02_status" == "404" ]]; then
  call_http "GET" "/api/ready" ""
  step02_call="$CALL_JSON"
  step02_status="$(jq -r '.status' <<<"$step02_call")"
fi
step02_body_ok="$(jq -r 'if (.response|type)=="object" then (.response.ok // false) else false end' <<<"$step02_call")"
step02_ok="false"
step02_note="Expected HTTP 200 and ok=true"
if [[ "$step02_status" == "200" && "$step02_body_ok" == "true" ]]; then
  step02_ok="true"
  step02_note="Ready responded with ok=true"
fi
step02_payload="$(jq -n --argjson call "$step02_call" --arg expected "status=200 and ok=true" '{call:$call,expected:$expected}')"
step02_duration="$(jq -r '.duration_ms // 0' <<<"$step02_call")"
step02_traces="$(jq -c '[.trace_id // empty] | map(select(length>0))' <<<"$step02_call")"
write_step "02_ready" "02_ready.json" "$step02_ok" "$step02_status" "$step02_note" "$step02_duration" "$step02_traces" "$step02_payload"

# Step 03: Auth
AUTH_OPERATIONS='[]'
AUTH_MODE='none'
AUTH_NOTE=''
NEED_USER_INPUT='false'

auth_add_op() {
  local op_json="$1"
  AUTH_OPERATIONS="$(jq -cn --argjson current "$AUTH_OPERATIONS" --argjson op "$op_json" '$current + [$op]')"
}

if [[ -n "$ACCESS_TOKEN" ]]; then
  AUTH_MODE='access_token'
  AUTH_NOTE='Using SMOKE_ACCESS_TOKEN'
else
  AUTH_MODE='otp'
  if [[ -z "$SMOKE_PHONE_VALUE" ]]; then
    AUTH_NOTE='SMOKE_PHONE_E164 is required when SMOKE_ACCESS_TOKEN is not set'
  else
    otp_request_body="$(jq -n --arg phone "$SMOKE_PHONE_VALUE" '{phone_e164:$phone}')"
    call_http "POST" "/auth/otp/request" "$otp_request_body"
    otp_req_call="$CALL_JSON"
    auth_add_op "$otp_req_call"

    if [[ -z "$SMOKE_OTP_VALUE" ]]; then
      NEED_USER_INPUT='true'
      AUTH_NOTE='OTP requested. Re-run with SMOKE_OTP_CODE=XXXXXX'
    else
      otp_verify_body="$(jq -n --arg phone "$SMOKE_PHONE_VALUE" --arg code "$SMOKE_OTP_VALUE" '{phone_e164:$phone,code:$code}')"
      call_http "POST" "/auth/otp/verify" "$otp_verify_body"
      otp_verify_call="$CALL_JSON"
      auth_add_op "$otp_verify_call"

      ACCESS_TOKEN="$(jq -r 'if (.response|type)=="object" then (.response.access_token // .response.token // .response.data.access_token // .response.data.token // empty) else empty end' <<<"$otp_verify_call")"
      if [[ -n "$ACCESS_TOKEN" ]]; then
        AUTH_NOTE='OTP flow verified and access token acquired'
      else
        AUTH_NOTE='OTP verify did not return access token'
      fi
    fi
  fi
fi

step03_ok="false"
step03_status="auth_failed"
step03_artifact="03_auth.json"
if [[ "$NEED_USER_INPUT" == "true" ]]; then
  step03_status="needs_input"
  step03_artifact="03_auth_need_input.json"
elif [[ -n "$ACCESS_TOKEN" ]]; then
  step03_ok="true"
  step03_status="ok"
fi
if [[ -z "$AUTH_NOTE" ]]; then
  AUTH_NOTE='Authentication flow completed'
fi
step03_duration="$(jq -r '[.[].duration_ms // 0] | add // 0' <<<"$AUTH_OPERATIONS")"
step03_traces="$(jq -c '[.[].trace_id // empty] | map(select(length>0)) | unique' <<<"$AUTH_OPERATIONS")"
step03_payload="$(jq -n --arg auth_mode "$AUTH_MODE" --arg note "$AUTH_NOTE" --arg token_acquired "$(json_bool "$step03_ok")" --arg access_token_preview "$(redact_token "$ACCESS_TOKEN")" --arg needs_input "$(json_bool "$NEED_USER_INPUT")" --argjson operations "$AUTH_OPERATIONS" '{auth_mode:$auth_mode,token_acquired:($token_acquired=="true"),needs_input:($needs_input=="true"),access_token_preview:$access_token_preview,note:$note,operations:$operations}')"
write_step "03_auth" "$step03_artifact" "$step03_ok" "$step03_status" "$AUTH_NOTE" "$step03_duration" "$step03_traces" "$step03_payload"

if [[ "$NEED_USER_INPUT" == "true" ]]; then
  steps_json="$(jq -s '.' "$STEPS_FILE")"
  failures_json="$(jq -s '.' "$FAILURES_FILE")"
  trace_ids_json="$(jq -s '[.[] | .trace_ids[]?] | map(select(type=="string" and length>0)) | unique' "$STEPS_FILE")"
  total_duration_ms="$(jq -s '[.[] | (.duration_ms // 0)] | add // 0' "$STEPS_FILE")"
  summary_json="$(jq -n \
    --argjson ok false \
    --arg base_url "$BASE_URL" \
    --arg env "$TARGET_ENV" \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg artifact_dir "$RUN_DIR" \
    --argjson total_duration_ms "$total_duration_ms" \
    --argjson steps "$steps_json" \
    --argjson failures "$failures_json" \
    --argjson trace_ids "$trace_ids_json" \
    '{ok:$ok,base_url:$base_url,env:$env,generated_at:$generated_at,total_duration_ms:$total_duration_ms,steps:$steps,failures:$failures,trace_ids:$trace_ids,artifact_dir:$artifact_dir}')"
  printf '%s\n' "$summary_json" >"${RUN_DIR}/summary.json"
  echo "OTP requested. Re-run with SMOKE_OTP_CODE=XXXXXX"
  echo "summary: ${RUN_DIR}/summary.json"
  exit 2
fi

# Shared state
OFFER_ID=''
PURCHASE_ID=''
INTENT_ID=''
TRIP_ID=''

# Step 04: Offers
if [[ -n "$ACCESS_TOKEN" ]]; then
  call_http "GET" "/marketplace/offers?limit=5" "" "authorization: Bearer ${ACCESS_TOKEN}"
  step04_call="$CALL_JSON"
  step04_status="$(jq -r '.status' <<<"$step04_call")"
  OFFER_ID="$(jq -r 'if (.response|type)=="object" then ((try .response.data[0].id catch empty) // (try .response.offers[0].id catch empty) // (try .response.data.offers[0].id catch empty) // empty) else empty end' <<<"$step04_call")"
  step04_ok="false"
  step04_note='Expected HTTP 200 and at least one offer id'
  if [[ "$step04_status" == "200" && -n "$OFFER_ID" ]]; then
    step04_ok="true"
    step04_note="Selected offer_id=${OFFER_ID}"
  fi
  step04_duration="$(jq -r '.duration_ms // 0' <<<"$step04_call")"
  step04_traces="$(jq -c '[.trace_id // empty] | map(select(length>0))' <<<"$step04_call")"
  step04_payload="$(jq -n --arg offer_id "$OFFER_ID" --argjson call "$step04_call" '{offer_id:$offer_id,call:$call}')"
  write_step "04_offers" "04_offers.json" "$step04_ok" "$step04_status" "$step04_note" "$step04_duration" "$step04_traces" "$step04_payload"
else
  write_step "04_offers" "04_offers.json" "false" "missing_auth" "Access token unavailable" "0" "[]" '{"error":"missing_access_token"}'
fi

# Step 05: Purchase create
if [[ -n "$ACCESS_TOKEN" && -n "$OFFER_ID" ]]; then
  purchase_body="$(jq -n --arg offer_id "$OFFER_ID" '{offer_id:$offer_id,quantity:1}')"
  purchase_idem="smoke-purchase-$(uuidish)"
  call_http "POST" "/marketplace/purchases" "$purchase_body" "authorization: Bearer ${ACCESS_TOKEN}" "idempotency-key: ${purchase_idem}"
  step05_call="$CALL_JSON"
  step05_status="$(jq -r '.status' <<<"$step05_call")"
  PURCHASE_ID="$(jq -r 'if (.response|type)=="object" then (.response.data.purchase_id // .response.data.purchase.purchase_id // .response.data.purchase.id // .response.purchase_id // .response.purchase.purchase_id // .response.purchase.id // empty) else empty end' <<<"$step05_call")"
  step05_ok="false"
  step05_note='Expected HTTP 200/201 and purchase_id'
  if [[ ( "$step05_status" == "200" || "$step05_status" == "201" ) && -n "$PURCHASE_ID" ]]; then
    step05_ok="true"
    step05_note="Created purchase_id=${PURCHASE_ID}"
  fi
  step05_duration="$(jq -r '.duration_ms // 0' <<<"$step05_call")"
  step05_traces="$(jq -c '[.trace_id // empty] | map(select(length>0))' <<<"$step05_call")"
  step05_payload="$(jq -n --arg purchase_id "$PURCHASE_ID" --argjson call "$step05_call" '{purchase_id:$purchase_id,call:$call}')"
  write_step "05_purchase_create" "05_purchase_create.json" "$step05_ok" "$step05_status" "$step05_note" "$step05_duration" "$step05_traces" "$step05_payload"
else
  write_step "05_purchase_create" "05_purchase_create.json" "false" "prerequisite_missing" "Requires access token and offer id" "0" "[]" '{"error":"missing_prerequisites"}'
fi

# Step 06: Intent create
if [[ -n "$ACCESS_TOKEN" && -n "$PURCHASE_ID" ]]; then
  intent_body="$(jq -n --arg purchase_id "$PURCHASE_ID" '{purchase_id:$purchase_id}')"
  intent_idem="smoke-intent-$(uuidish)"
  call_http "POST" "/payments/intents" "$intent_body" "authorization: Bearer ${ACCESS_TOKEN}" "idempotency-key: ${intent_idem}"
  step06_call="$CALL_JSON"
  step06_status="$(jq -r '.status' <<<"$step06_call")"
  INTENT_ID="$(jq -r 'if (.response|type)=="object" then (.response.data.id // .response.id // empty) else empty end' <<<"$step06_call")"
  step06_ok="false"
  step06_note='Expected HTTP 200 and intent id'
  if [[ "$step06_status" == "200" && -n "$INTENT_ID" ]]; then
    step06_ok="true"
    step06_note="Created intent_id=${INTENT_ID}"
  fi
  step06_duration="$(jq -r '.duration_ms // 0' <<<"$step06_call")"
  step06_traces="$(jq -c '[.trace_id // empty] | map(select(length>0))' <<<"$step06_call")"
  step06_payload="$(jq -n --arg intent_id "$INTENT_ID" --argjson call "$step06_call" '{intent_id:$intent_id,call:$call}')"
  write_step "06_intent_create" "06_intent_create.json" "$step06_ok" "$step06_status" "$step06_note" "$step06_duration" "$step06_traces" "$step06_payload"
else
  write_step "06_intent_create" "06_intent_create.json" "false" "prerequisite_missing" "Requires access token and purchase id" "0" "[]" '{"error":"missing_prerequisites"}'
fi
# Step 07: Webhook simulation (staging/test mode only)
run_webhook_sim="false"
allow_webhook_sim="false"
ALLOW_PENDING_PURCHASE="false"
step07_skip_reason=''
if [[ "$SMOKE_WEBHOOK_SIM_VALUE" == "true" && "$TARGET_ENV" != "prod" && "$TARGET_ENV" != "production" && -n "$PURCHASE_ID" ]]; then
  allow_webhook_sim="true"
fi

if [[ "$allow_webhook_sim" == "true" ]]; then
  if [[ -z "$PAYSTACK_WEBHOOK_SECRET_VALUE" ]]; then
    step07_skip_reason='Webhook simulation skipped: PAYSTACK_WEBHOOK_SECRET not provided to ops runtime'
  else
    run_webhook_sim="true"
  fi
elif [[ "$SMOKE_WEBHOOK_SIM_VALUE" != "true" ]]; then
  step07_skip_reason='Webhook simulation disabled by SMOKE_WEBHOOK_SIM=false'
elif [[ "$TARGET_ENV" == "prod" || "$TARGET_ENV" == "production" ]]; then
  step07_skip_reason='Webhook simulation disabled in production environment'
else
  step07_skip_reason='Webhook simulation skipped because purchase_id is unavailable'
fi

if [[ "$run_webhook_sim" == "true" ]]; then
  provider_event_id="evt-smoke-$(uuidish)"
  webhook_payload="$(jq -n --arg event_id "$provider_event_id" --arg purchase_id "$PURCHASE_ID" '{provider_event_id:$event_id,event_id:$event_id,event_type:"payment_succeeded",purchase_id:$purchase_id,event:"charge.success",data:{id:$event_id,metadata:{purchase_id:$purchase_id}}}')"
  webhook_headers=()
  if [[ -n "$WEBHOOK_SECRET_VALUE" ]]; then
    webhook_sig="$(printf '%s' "$webhook_payload" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET_VALUE" -hex | awk '{print $NF}')"
    webhook_headers+=("x-webhook-signature: ${webhook_sig}")
  fi
  paystack_sig="$(printf '%s' "$webhook_payload" | openssl dgst -sha512 -hmac "$PAYSTACK_WEBHOOK_SECRET_VALUE" -hex | awk '{print $NF}')"
  webhook_headers+=("x-paystack-signature: ${paystack_sig}")
  webhook_headers+=("x-paystack-event-id: ${provider_event_id}")

  call_http "POST" "/webhooks/payments" "$webhook_payload" "${webhook_headers[@]}"
  step07_call="$CALL_JSON"
  step07_status="$(jq -r '.status' <<<"$step07_call")"
  step07_ok="false"
  step07_note='Expected HTTP 200/202 from webhook simulation'
  if [[ "$step07_status" == "200" || "$step07_status" == "202" ]]; then
    step07_ok="true"
    step07_note='Webhook simulation accepted'
  elif [[ "$step07_status" == "404" || "$step07_status" == "405" ]]; then
    step07_ok="true"
    step07_status="skipped"
    ALLOW_PENDING_PURCHASE="true"
    step07_skip_reason='Webhook simulation endpoint unavailable on target'
    step07_note="$step07_skip_reason"
  fi
  step07_duration="$(jq -r '.duration_ms // 0' <<<"$step07_call")"
  step07_traces="$(jq -c '[.trace_id // empty] | map(select(length>0))' <<<"$step07_call")"
  step07_payload="$(jq -n --arg provider_event_id "$provider_event_id" --arg skipped_reason "$step07_skip_reason" --argjson call "$step07_call" '{provider_event_id:$provider_event_id,skipped_reason:$skipped_reason,call:$call}')"
  write_step "07_webhook_sim" "07_webhook_sim.json" "$step07_ok" "$step07_status" "$step07_note" "$step07_duration" "$step07_traces" "$step07_payload"
else
  ALLOW_PENDING_PURCHASE="true"
  write_step "07_webhook_sim" "07_webhook_sim.json" "true" "skipped" "$step07_skip_reason" "0" "[]" "$(jq -n --arg reason "$step07_skip_reason" '{skipped:true,skipped_reason:$reason}')"
fi

# Step 08: Purchase polling
if [[ -n "$ACCESS_TOKEN" && -n "$PURCHASE_ID" ]]; then
  poll_ops='[]'
  poll_start="$(now_ms)"
  deadline_ms=$(( poll_start + 45000 ))
  final_status=''
  terminal_outcome='timeout'
  while true; do
    call_http "GET" "/marketplace/purchases/${PURCHASE_ID}" "" "authorization: Bearer ${ACCESS_TOKEN}"
    poll_call="$CALL_JSON"
    poll_ops="$(jq -cn --argjson current "$poll_ops" --argjson op "$poll_call" '$current + [$op]')"
    poll_http_status="$(jq -r '.status' <<<"$poll_call")"
    final_status="$(jq -r 'if (.response|type)=="object" then ((.response.data.status // .response.data.purchase.status // .response.status // .response.purchase.status // "") | tostring | ascii_downcase) else "" end' <<<"$poll_call")"

    if [[ "$poll_http_status" != "200" ]]; then
      terminal_outcome='http_error'
      break
    fi
    if [[ "$final_status" == "paid" || "$final_status" == "active" ]]; then
      terminal_outcome='paid'
      break
    fi
    if [[ "$ALLOW_PENDING_PURCHASE" == "true" && ( "$final_status" == "pending_payment" || "$final_status" == "pending" ) ]]; then
      terminal_outcome='pending'
      break
    fi
    if [[ "$final_status" == "failed" || "$final_status" == "canceled" || "$final_status" == "cancelled" ]]; then
      terminal_outcome='failed'
      break
    fi

    now="$(now_ms)"
    if (( now >= deadline_ms )); then
      terminal_outcome='timeout'
      break
    fi
    sleep 3
  done

  step08_ok="false"
  step08_status="$terminal_outcome"
  step08_note="Purchase status=${final_status:-unknown}"
  if [[ "$terminal_outcome" == "paid" || ( "$ALLOW_PENDING_PURCHASE" == "true" && "$terminal_outcome" == "pending" ) ]]; then
    step08_ok="true"
    step08_status="ok"
    if [[ "$terminal_outcome" == "paid" ]]; then
      step08_note="Purchase reached terminal paid state (${final_status})"
    else
      step08_note="Purchase remained pending as expected when webhook simulation is skipped (${final_status})"
    fi
  fi

  step08_duration="$(( $(now_ms) - poll_start ))"
  step08_traces="$(jq -c '[.[].trace_id // empty] | map(select(length>0)) | unique' <<<"$poll_ops")"
  step08_payload="$(jq -n --arg purchase_id "$PURCHASE_ID" --arg final_status "$final_status" --arg terminal_outcome "$terminal_outcome" --argjson attempts "$poll_ops" '{purchase_id:$purchase_id,final_status:$final_status,terminal_outcome:$terminal_outcome,attempts:$attempts}')"
  write_step "08_purchase_poll" "08_purchase_poll.json" "$step08_ok" "$step08_status" "$step08_note" "$step08_duration" "$step08_traces" "$step08_payload"
else
  write_step "08_purchase_poll" "08_purchase_poll.json" "false" "prerequisite_missing" "Requires access token and purchase id" "0" "[]" '{"error":"missing_prerequisites"}'
fi

# Step 09: Dispatch quote
if [[ -n "$ACCESS_TOKEN" ]]; then
  quote_body='{"pickup":{"lat":6.455,"lng":3.384},"dropoff":{"lat":6.6018,"lng":3.3515},"service_level":"standard"}'
  call_http "POST" "/dispatch/quote" "$quote_body" "authorization: Bearer ${ACCESS_TOKEN}"
  step09_call="$CALL_JSON"
  step09_status="$(jq -r '.status' <<<"$step09_call")"
  price_minor="$(jq -r 'if (.response|type)=="object" then (.response.price_minor // empty) else empty end' <<<"$step09_call")"
  distance_km="$(jq -r 'if (.response|type)=="object" then (.response.distance_km // empty) else empty end' <<<"$step09_call")"
  step09_ok="false"
  step09_note='Expected HTTP 200 with distance_km, duration_min_est, price_minor, currency'
  has_required_fields="$(jq -r 'if (.response|type)=="object" then ((.response.distance_km != null) and (.response.duration_min_est != null) and (.response.price_minor != null) and ((.response.currency // "") | tostring | length > 0)) else false end' <<<"$step09_call")"
  if [[ "$step09_status" == "200" && "$has_required_fields" == "true" ]]; then
    step09_ok="true"
    step09_note="Quote validated (price_minor=${price_minor}, distance_km=${distance_km})"
  fi
  step09_duration="$(jq -r '.duration_ms // 0' <<<"$step09_call")"
  step09_traces="$(jq -c '[.trace_id // empty] | map(select(length>0))' <<<"$step09_call")"
  step09_payload="$(jq -n --argjson call "$step09_call" '{call:$call}')"
  write_step "09_quote" "09_quote.json" "$step09_ok" "$step09_status" "$step09_note" "$step09_duration" "$step09_traces" "$step09_payload"
else
  write_step "09_quote" "09_quote.json" "false" "missing_auth" "Access token unavailable" "0" "[]" '{"error":"missing_access_token"}'
fi

# Step 10: Trip create
if [[ -n "$ACCESS_TOKEN" ]]; then
  trip_body='{"pickup":{"lat":6.455,"lng":3.384,"address":"Lagos Island"},"dropoff":{"lat":6.6018,"lng":3.3515,"address":"Ikeja"},"notes":"smoke run"}'
  call_http "POST" "/dispatch/trips" "$trip_body" "authorization: Bearer ${ACCESS_TOKEN}"
  step10_call="$CALL_JSON"
  step10_status="$(jq -r '.status' <<<"$step10_call")"
  TRIP_ID="$(jq -r 'if (.response|type)=="object" then (.response.trip.id // .response.data.trip.id // empty) else empty end' <<<"$step10_call")"
  step10_ok="false"
  step10_note='Expected HTTP 200/201 and trip id'
  if [[ ( "$step10_status" == "200" || "$step10_status" == "201" ) && -n "$TRIP_ID" ]]; then
    step10_ok="true"
    step10_note="Created trip_id=${TRIP_ID}"
  fi
  step10_duration="$(jq -r '.duration_ms // 0' <<<"$step10_call")"
  step10_traces="$(jq -c '[.trace_id // empty] | map(select(length>0))' <<<"$step10_call")"
  step10_payload="$(jq -n --arg trip_id "$TRIP_ID" --argjson call "$step10_call" '{trip_id:$trip_id,call:$call}')"
  write_step "10_trip_create" "10_trip_create.json" "$step10_ok" "$step10_status" "$step10_note" "$step10_duration" "$step10_traces" "$step10_payload"
else
  write_step "10_trip_create" "10_trip_create.json" "false" "missing_auth" "Access token unavailable" "0" "[]" '{"error":"missing_access_token"}'
fi

# Step 11: Trip status + assignment + delivery verify
if [[ -n "$ACCESS_TOKEN" && -n "$TRIP_ID" ]]; then
  trip_ops='[]'
  trip_status_start="$(now_ms)"
  trip_step_ok="true"
  trip_note='Trip reached delivered state'
  assign_supported='unknown'

  trip_add_op() {
    local op_json="$1"
    trip_ops="$(jq -cn --argjson current "$trip_ops" --argjson op "$op_json" '$current + [$op]')"
  }

  # created -> searching
  call_http "POST" "/dispatch/trips/${TRIP_ID}/status" '{"status":"searching"}' "authorization: Bearer ${ACCESS_TOKEN}"
  status_searching_call="$CALL_JSON"
  trip_add_op "$status_searching_call"
  if [[ "$(jq -r '.status' <<<"$status_searching_call")" != "200" ]]; then
    trip_step_ok="false"
    trip_note='Failed to transition trip to searching'
  fi

  DRIVER_ID="$SMOKE_DRIVER_ID_VALUE"
  if [[ "$trip_step_ok" == "true" && -z "$DRIVER_ID" ]]; then
    driver_stamp="$(date -u +%s)"
    driver_email="smoke.driver.${driver_stamp}@hailo.dev"
    driver_password='Passw0rd!'
    register_body="$(jq -n --arg email "$driver_email" --arg pass "$driver_password" '{email:$email,password:$pass,role:"driver",display_name:"Smoke Driver"}')"
    call_http "POST" "/auth/register" "$register_body" "idempotency-key: smoke-driver-${driver_stamp}"
    driver_register_call="$CALL_JSON"
    trip_add_op "$driver_register_call"
    register_status="$(jq -r '.status' <<<"$driver_register_call")"
    if [[ "$register_status" != "201" ]]; then
      trip_step_ok="false"
      trip_note='Failed to create smoke driver account'
    else
      DRIVER_ID="$(jq -r 'if (.response|type)=="object" then (.response.user_id // .response.data.user_id // .response.user.id // empty) else empty end' <<<"$driver_register_call")"
    fi

    if [[ "$trip_step_ok" == "true" && -z "$DRIVER_ID" ]]; then
      trip_step_ok="false"
      trip_note='Driver creation succeeded but user_id was missing'
    fi
  fi

  if [[ "$trip_step_ok" == "true" ]]; then
    assign_body="$(jq -n --arg driver_id "$DRIVER_ID" '{driver_id:$driver_id}')"
    call_http "POST" "/dispatch/trips/${TRIP_ID}/assign" "$assign_body" "authorization: Bearer ${ACCESS_TOKEN}"
    assign_call="$CALL_JSON"
    trip_add_op "$assign_call"
    assign_status="$(jq -r '.status' <<<"$assign_call")"

    if [[ "$assign_status" == "200" ]]; then
      assign_supported='true'
    elif [[ "$assign_status" == "404" || "$assign_status" == "405" ]]; then
      assign_supported='false'
      call_http "POST" "/dispatch/trips/${TRIP_ID}/status" '{"status":"assigned"}' "authorization: Bearer ${ACCESS_TOKEN}"
      status_assigned_call="$CALL_JSON"
      trip_add_op "$status_assigned_call"
      if [[ "$(jq -r '.status' <<<"$status_assigned_call")" != "200" ]]; then
        trip_step_ok="false"
        trip_note='Assign endpoint unavailable and fallback status transition failed'
      fi
    else
      trip_step_ok="false"
      trip_note='Assign call failed unexpectedly'
    fi
  fi

  for transition in enroute_pickup picked_up enroute_dropoff delivered; do
    if [[ "$trip_step_ok" != "true" ]]; then
      break
    fi
    transition_body="$(jq -n --arg status "$transition" '{status:$status}')"
    call_http "POST" "/dispatch/trips/${TRIP_ID}/status" "$transition_body" "authorization: Bearer ${ACCESS_TOKEN}"
    transition_call="$CALL_JSON"
    trip_add_op "$transition_call"
    if [[ "$(jq -r '.status' <<<"$transition_call")" != "200" ]]; then
      trip_step_ok="false"
      trip_note="Failed transition to ${transition}"
      break
    fi
  done

  if [[ "$trip_step_ok" == "true" ]]; then
    call_http "GET" "/dispatch/trips/${TRIP_ID}" "" "authorization: Bearer ${ACCESS_TOKEN}"
    trip_get_call="$CALL_JSON"
    trip_add_op "$trip_get_call"
    if [[ "$(jq -r '.status' <<<"$trip_get_call")" != "200" ]]; then
      trip_step_ok="false"
      trip_note='Failed to fetch trip after transitions'
    else
      final_trip_status="$(jq -r 'if (.response|type)=="object" then ((.response.trip.status // .response.data.trip.status // "") | tostring | ascii_downcase) else "" end' <<<"$trip_get_call")"
      if [[ "$final_trip_status" != "delivered" ]]; then
        trip_step_ok="false"
        trip_note="Trip final status is ${final_trip_status:-missing}, expected delivered"
      fi
    fi
  fi

  step11_ok="$(json_bool "$trip_step_ok")"
  step11_status='ok'
  if [[ "$step11_ok" != "true" ]]; then
    step11_status='trip_flow_failed'
  fi
  step11_duration="$(( $(now_ms) - trip_status_start ))"
  step11_traces="$(jq -c '[.[].trace_id // empty] | map(select(length>0)) | unique' <<<"$trip_ops")"
  step11_payload="$(jq -n --arg trip_id "$TRIP_ID" --arg assign_supported "$assign_supported" --arg note "$trip_note" --argjson operations "$trip_ops" '{trip_id:$trip_id,assign_supported:$assign_supported,note:$note,operations:$operations}')"
  write_step "11_trip_status_flow" "11_trip_status_flow.json" "$step11_ok" "$step11_status" "$trip_note" "$step11_duration" "$step11_traces" "$step11_payload"
else
  write_step "11_trip_status_flow" "11_trip_status_flow.json" "false" "prerequisite_missing" "Requires access token and trip id" "0" "[]" '{"error":"missing_prerequisites"}'
fi
# Step 12: Admin metrics/users/trips (+ optional audit check)
admin_ops='[]'
admin_status='skipped'
admin_ok='true'
admin_note='Admin flow skipped (no admin access available)'

admin_add_op() {
  local op_json="$1"
  admin_ops="$(jq -cn --argjson current "$admin_ops" --argjson op "$op_json" '$current + [$op]')"
}

if [[ -n "$ACCESS_TOKEN" ]]; then
  call_http "GET" "/admin/metrics" "" "authorization: Bearer ${ACCESS_TOKEN}"
  bearer_admin_metrics_call="$CALL_JSON"
  admin_add_op "$bearer_admin_metrics_call"
  bearer_metrics_status="$(jq -r '.status' <<<"$bearer_admin_metrics_call")"
  if [[ "$bearer_metrics_status" == "200" ]]; then
    call_http "GET" "/admin/users?limit=5" "" "authorization: Bearer ${ACCESS_TOKEN}"
    bearer_admin_users_call="$CALL_JSON"
    admin_add_op "$bearer_admin_users_call"
    call_http "GET" "/admin/trips?limit=5" "" "authorization: Bearer ${ACCESS_TOKEN}"
    bearer_admin_trips_call="$CALL_JSON"
    admin_add_op "$bearer_admin_trips_call"

    if [[ "$(jq -r '.status' <<<"$bearer_admin_users_call")" == "200" && "$(jq -r '.status' <<<"$bearer_admin_trips_call")" == "200" ]]; then
      admin_status='ok'
      admin_ok='true'
      admin_note='Admin endpoints succeeded via bearer token'
    else
      admin_status='admin_flow_failed'
      admin_ok='false'
      admin_note='Admin bearer token flow failed for users/trips endpoints'
    fi
  elif [[ "$bearer_metrics_status" == "401" || "$bearer_metrics_status" == "403" ]]; then
    admin_status='skipped'
    admin_ok='true'
    admin_note='Admin endpoints unavailable for current bearer token (non-admin)'
  else
    admin_status='admin_flow_failed'
    admin_ok='false'
    admin_note='Admin metrics request failed unexpectedly'
  fi
fi

step12_duration="$(jq -r '[.[].duration_ms // 0] | add // 0' <<<"$admin_ops")"
step12_traces="$(jq -c '[.[].trace_id // empty] | map(select(length>0)) | unique' <<<"$admin_ops")"
step12_payload="$(jq -n --arg note "$admin_note" --argjson operations "$admin_ops" '{note:$note,operations:$operations}')"
write_step "12_admin_metrics" "12_admin_metrics.json" "$admin_ok" "$admin_status" "$admin_note" "$step12_duration" "$step12_traces" "$step12_payload"

steps_json="$(jq -s '.' "$STEPS_FILE")"
failures_json="$(jq -s '.' "$FAILURES_FILE")"
trace_ids_json="$(jq -s '[.[] | .trace_ids[]?] | map(select(type=="string" and length>0)) | unique' "$STEPS_FILE")"
total_duration_ms="$(jq -s '[.[] | (.duration_ms // 0)] | add // 0' "$STEPS_FILE")"

summary_json="$(jq -n \
  --argjson ok "$OVERALL_OK" \
  --arg base_url "$BASE_URL" \
  --arg env "$TARGET_ENV" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg artifact_dir "$RUN_DIR" \
  --argjson total_duration_ms "$total_duration_ms" \
  --argjson steps "$steps_json" \
  --argjson failures "$failures_json" \
  --argjson trace_ids "$trace_ids_json" \
  '{ok:$ok,base_url:$base_url,env:$env,generated_at:$generated_at,total_duration_ms:$total_duration_ms,steps:$steps,failures:$failures,trace_ids:$trace_ids,artifact_dir:$artifact_dir}')"
printf '%s\n' "$summary_json" >"${RUN_DIR}/summary.json"

if [[ "$OVERALL_OK" == "true" ]]; then
  echo "PASS: smoke e2e completed"
  echo "summary: ${RUN_DIR}/summary.json"
  exit 0
fi

echo "FAIL: smoke e2e encountered failures"
echo "summary: ${RUN_DIR}/summary.json"
exit 1
