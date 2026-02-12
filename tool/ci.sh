#!/usr/bin/env bash
set -euo pipefail

flutter --no-version-check --version
flutter --no-version-check pub get
flutter --no-version-check analyze
flutter --no-version-check test
