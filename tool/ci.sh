#!/usr/bin/env bash
set -euo pipefail

flutter --no-version-check --version
flutter --no-version-check pub get
flutter --no-version-check analyze

if [[ "${CI_FULL:-0}" == "1" ]]; then
  flutter --no-version-check test --concurrency=1
else
  flutter --no-version-check test --concurrency=1 \
    test/domain \
    test/services \
    test/data \
    test/reliability \
    test/threats \
    test/sync
fi
