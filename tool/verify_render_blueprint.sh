#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RENDER_FILE="$ROOT_DIR/render.yaml"

if [[ ! -f "$RENDER_FILE" ]]; then
  echo "render.yaml not found at $RENDER_FILE"
  exit 1
fi

if grep -Eq '^[[:space:]]*(dockerCommand|startCommand)[[:space:]]*:' "$RENDER_FILE"; then
  echo "render.yaml must not define dockerCommand/startCommand overrides; use Dockerfile CMD only."
  exit 1
fi

assert_service() {
  local name="$1"
  local type="$2"
  local dockerfile="$3"
  local root_dir="$4"

  if ! awk -v svc="$name" -v typ="$type" -v root="$root_dir" -v docker="$dockerfile" '
    function trim(v) { sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v); return v }
    function flush_block() {
      if (in_block && block_name == svc) {
        if (block_type != typ) {
          print "Service \"" svc "\" must be type \"" typ "\""
          exit 2
        }
        if (block_root != root) {
          print "Service \"" svc "\" must use rootDir \"" root "\""
          exit 3
        }
        if (block_docker != docker) {
          print "Service \"" svc "\" must use dockerfilePath \"" docker "\""
          exit 4
        }
        found = 1
      }
    }
    {
      line = $0
      if (line ~ /^  -[[:space:]]*type:[[:space:]]*/) {
        flush_block()
        in_block = 1
        block_type = line
        sub(/^  -[[:space:]]*type:[[:space:]]*/, "", block_type)
        block_type = trim(block_type)
        block_name = ""
        block_root = ""
        block_docker = ""
        next
      }
      if (!in_block) {
        next
      }
      if (line ~ /^    name:[[:space:]]*/) {
        block_name = line
        sub(/^    name:[[:space:]]*/, "", block_name)
        block_name = trim(block_name)
        next
      }
      if (line ~ /^    rootDir:[[:space:]]*/) {
        block_root = line
        sub(/^    rootDir:[[:space:]]*/, "", block_root)
        block_root = trim(block_root)
        next
      }
      if (line ~ /^    dockerfilePath:[[:space:]]*/) {
        block_docker = line
        sub(/^    dockerfilePath:[[:space:]]*/, "", block_docker)
        block_docker = trim(block_docker)
        next
      }
    }
    END {
      flush_block()
      if (!found) {
        print "Missing required Render service \"" svc "\""
        exit 1
      }
    }
  ' "$RENDER_FILE"; then
    exit 1
  fi

  if [[ ! -f "$ROOT_DIR/$dockerfile" ]]; then
    echo "dockerfilePath for '$name' does not exist at $ROOT_DIR/$dockerfile"
    exit 1
  fi
}

assert_service "hail-o-ci" "worker" "Dockerfile.ci" "."
assert_service "hail-o-api" "web" "backend/Dockerfile" "."
assert_service "hail-o-api-staging" "web" "backend/Dockerfile" "."

echo "Render blueprint verification: PASS"
