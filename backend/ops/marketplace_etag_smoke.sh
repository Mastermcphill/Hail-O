#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${HAILO_API_BASE_URL:-http://127.0.0.1:8080}"
OFFERS_URL="${BASE_URL%/}/api/marketplace/offers"
HEADERS_1="$(mktemp)"
BODY_1="$(mktemp)"
HEADERS_2="$(mktemp)"
BODY_2="$(mktemp)"

cleanup() {
  rm -f "$HEADERS_1" "$BODY_1" "$HEADERS_2" "$BODY_2"
}

fail() {
  echo "FAIL: $1"
  exit 1
}

trap cleanup EXIT

status_1="$(
  curl -sS -D "$HEADERS_1" -o "$BODY_1" -w "%{http_code}" "$OFFERS_URL"
)"
if [[ "$status_1" != "200" ]]; then
  fail "expected 200 from ${OFFERS_URL}, got ${status_1}"
fi

etag="$(
  awk 'BEGIN{IGNORECASE=1} /^etag:/ {sub(/\r$/, "", $0); sub(/^[^:]*:[[:space:]]*/, "", $0); print; exit}' "$HEADERS_1"
)"
if [[ -z "$etag" ]]; then
  fail "missing ETag header on first offers response"
fi

status_2="$(
  curl -sS -D "$HEADERS_2" -o "$BODY_2" -w "%{http_code}" \
    -H "If-None-Match: ${etag}" \
    "$OFFERS_URL"
)"
if [[ "$status_2" != "304" ]]; then
  fail "expected 304 on If-None-Match replay, got ${status_2}"
fi

body_2_size="$(wc -c < "$BODY_2" | tr -d '[:space:]')"
if [[ "$body_2_size" != "0" ]]; then
  fail "expected empty body on 304, got ${body_2_size} bytes"
fi

content_length="$(
  awk 'BEGIN{IGNORECASE=1} /^content-length:/ {sub(/\r$/, "", $0); sub(/^[^:]*:[[:space:]]*/, "", $0); print; exit}' "$HEADERS_2"
)"
if [[ -n "$content_length" && "$content_length" != "0" ]]; then
  fail "expected content-length 0 (or absent) on 304, got ${content_length}"
fi

x_error_code="$(
  awk 'BEGIN{IGNORECASE=1} /^x-error-code:/ {sub(/\r$/, "", $0); sub(/^[^:]*:[[:space:]]*/, "", $0); print; exit}' "$HEADERS_2"
)"
if [[ -n "$x_error_code" ]]; then
  fail "unexpected x-error-code on 304 response: ${x_error_code}"
fi

echo "PASS marketplace etag smoke"
echo "URL: ${OFFERS_URL}"
echo "ETag: ${etag}"
