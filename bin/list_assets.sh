#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="ptekwpdev_assets"
OUTPUT_FORMAT="text"
TYPE=""

usage() {
  echo "Usage: $0 [--type <plugin|theme|static>] [--json]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) TYPE="$2"; shift 2 ;;
    --json) OUTPUT_FORMAT="json"; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# Check if container exists and is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "❌ Container [$CONTAINER_NAME] is not running."
  echo "👉 Please start it first: assets.sh --action up"
  exit 1
fi

list_type_text() {
  local type="$1"
  echo "Listing ${type}s in container [$CONTAINER_NAME]..."
  docker exec "$CONTAINER_NAME" ls -1 "/var/www/assets/${type}s" | while read -r version; do
    echo "Version: $version"
    docker exec "$CONTAINER_NAME" ls -1 "/var/www/assets/${type}s/$version" | while read -r item; do
      echo "• $item"
    done
  done
}

list_type_json() {
  local type="$1"
  echo "{"
  echo "  \"${type}s\": ["
  first_version=true
  for version in $(docker exec "$CONTAINER_NAME" ls -1 "/var/www/assets/${type}s"); do
    $first_version || echo "    ,"
    first_version=false
    echo "    {"
    echo "      \"version\": \"$version\","
    echo "      \"items\": ["
    first_item=true
    for item in $(docker exec "$CONTAINER_NAME" ls -1 "/var/www/assets/${type}s/$version"); do
      $first_item || echo "        ,"
      first_item=false
      echo "        \"$item\""
    done
    echo "      ]"
    echo "    }"
  done
  echo "  ]"
  echo "}"
}

if [[ -z "$TYPE" ]]; then
  echo "Please specify --type <plugin|theme|static> for structured listing."
  exit 1
fi

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  list_type_json "$TYPE"
else
  list_type_text "$TYPE"
fi