#!/usr/bin/env bash
set -euo pipefail

dart --version
which dart
echo "hail-o backend startup: db_mode=${BACKEND_DB_MODE:-unset} env=${ENV:-unset} commit=${RENDER_GIT_COMMIT:-local}"

dart run bin/migrate.dart
exec dart run bin/server.dart
