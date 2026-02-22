#!/usr/bin/env bash
set -euo pipefail

export STARTUP_RUNTIME_MARKER="entrypoint_dart_ok"
export DART_SDK_VERSION="$(dart --version 2>&1 | head -n 1)"
echo "$DART_SDK_VERSION"
which dart
echo "hail-o backend startup: db_mode=${BACKEND_DB_MODE:-unset} env=${ENV:-unset} commit=${RENDER_GIT_COMMIT:-local}"

dart run bin/migrate.dart
exec dart run bin/server.dart
