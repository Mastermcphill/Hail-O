#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
PORT_VALUE=9999
LOG_FILE="$(mktemp)"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f "$LOG_FILE"
}

trap cleanup EXIT

cd "$BACKEND_DIR"

export PORT="$PORT_VALUE"
export BACKEND_DB_MODE="${BACKEND_DB_MODE:-sqlite}"

dart run bin/server.dart >"$LOG_FILE" 2>&1 &
SERVER_PID="$!"

for _ in $(seq 1 60); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "server exited before bind contract completed"
    cat "$LOG_FILE"
    exit 1
  fi
  if rg -q "\"event\":\"server_listen\"" "$LOG_FILE"; then
    break
  fi
  sleep 0.5
done

if ! rg -q "\"event\":\"server_listen\".*\"host\":\"0.0.0.0\".*\"port\":${PORT_VALUE}" "$LOG_FILE"; then
  echo "missing expected server_listen log (host=0.0.0.0 port=${PORT_VALUE})"
  cat "$LOG_FILE"
  exit 1
fi

curl -fsS "http://127.0.0.1:${PORT_VALUE}/healthz" >/dev/null
curl -fsS "http://127.0.0.1:${PORT_VALUE}/api/healthz" >/dev/null

echo "render port contract passed"
