#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="ptekwpdev_assets"

usage() {
  echo "Usage: $0 [--type <plugin|theme|static>]"
  exit 1
}

TYPE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) TYPE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

list_all() {
  echo "Listing all assets in container [$CONTAINER_NAME]..."
  docker exec "$CONTAINER_NAME" ls -1 /var/www/assets
}

list_type() {
  local type="$1"
  echo "Listing ${type}s in container [$CONTAINER_NAME]..."
  docker exec "$CONTAINER_NAME" ls -1 "/var/www/assets/${type}s" | while read -r item; do
    if [[ "$item" =~ -(v?[0-9]+\.[0-9]+(\.[0-9]+)?)$ ]]; then
      base="${item%-*}"
      version="${item##*-}"
      echo "• $base (version: $version)"
    else
      echo "• $item (version: latest)"
    fi
  done
}

if [[ -z "$TYPE" ]]; then
  list_all
else
  list_type "$TYPE"
fi