#!/usr/bin/env bash
set -euo pipefail

export STARTUP_RUNTIME_MARKER="entrypoint_aot_server"
export DART_SDK_VERSION="$(dart --version 2>&1 | head -n 1)"
echo "$DART_SDK_VERSION"
which dart
echo "hail-o backend startup: db_mode=${BACKEND_DB_MODE:-unset} env=${ENV:-unset} commit=${RENDER_GIT_COMMIT:-local}"

# Keep PID 1 attached to the backend process so the container stays alive.
# The compiled server binary owns the full boot sequence, including migrations,
# so Render only pays for a single startup path.
exec /app/backend/build/bundle/bin/server
