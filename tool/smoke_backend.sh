#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${HAILO_API_BASE_URL:-https://hail-o-api.onrender.com}"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EMAIL="smoke.$(date -u +%s)@hailo.dev"
PASSWORD="${HAILO_SMOKE_PASSWORD:-Passw0rd!}"
REGISTER_KEY="smoke-register-$(date -u +%s%N)"
RIDE_KEY="smoke-ride-$(date -u +%s%N)"

echo "BASE_URL=$BASE_URL"
echo "EMAIL=$EMAIL"

echo
echo "=== HEALTH ==="
curl -sS -i "$BASE_URL/health"

echo
echo "=== REGISTER ==="
REGISTER_BODY="$(cat <<JSON
{"email":"$EMAIL","password":"$PASSWORD","role":"rider","display_name":"Smoke Rider"}
JSON
)"
curl -sS -i \
  -X POST "$BASE_URL/auth/register" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: $REGISTER_KEY" \
  --data "$REGISTER_BODY"

echo
echo "=== LOGIN ==="
LOGIN_BODY="$(cat <<JSON
{"email":"$EMAIL","password":"$PASSWORD"}
JSON
)"
LOGIN_RESPONSE="$(curl -sS \
  -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  --data "$LOGIN_BODY")"
echo "$LOGIN_RESPONSE"

TOKEN="$(echo "$LOGIN_RESPONSE" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
if [[ -z "$TOKEN" ]]; then
  echo "ERROR: missing token in login response"
  exit 1
fi

echo
echo "=== REQUEST RIDE ==="
RIDE_BODY="$(cat <<JSON
{
  "scheduled_departure_at":"$NOW_UTC",
  "trip_scope":"intra_city",
  "distance_meters":12000,
  "duration_seconds":1800,
  "luggage_count":1,
  "vehicle_class":"sedan",
  "base_fare_minor":100000,
  "premium_markup_minor":5000,
  "connection_fee_minor":5000
}
JSON
)"
curl -sS -i \
  -X POST "$BASE_URL/rides/request" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: $RIDE_KEY" \
  --data "$RIDE_BODY"
