#!/usr/bin/env bash
set -euo pipefail

dart --version
dart pub get
dart analyze
dart test
