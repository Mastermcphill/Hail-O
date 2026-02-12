#!/usr/bin/env bash
set -euo pipefail

if [ "${CI_FULL:-0}" = "1" ]; then
  echo "CI mode: FULL"
else
  echo "CI mode: FAST"
fi

flutter --version
flutter pub get
flutter analyze

if [ "${CI_FULL:-0}" = "1" ]; then
  flutter test --concurrency=1
else
  flutter test --concurrency=1 \
    test/domain \
    test/services \
    test/data \
    test/reliability \
    test/threats \
    test/sync
fi
