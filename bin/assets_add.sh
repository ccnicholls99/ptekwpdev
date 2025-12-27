#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — Add Asset to Shared Assets Container
#  Script: assets_add.sh
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail

# ------------------------------------------------------------------------------
# Preserve caller directory
# ------------------------------------------------------------------------------

PTEK_CALLER_PWD="$(pwd)"
ptekwp_cleanup() { cd "$PTEK_CALLER_PWD"; }
trap ptekwp_cleanup EXIT

# ------------------------------------------------------------------------------
# Load app config + logging
# ------------------------------------------------------------------------------

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/app_config.sh"

set_log --truncate "${PTEK_APP_LOG_DIR}/assets_add.log" \
  "=== Assets Add Run ($(date)) ==="

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------

ASSETS_CONTAINER="ptekwpdev_assets"
ASSETS_DOCKER_DIR="${PTEK_APP_ASSETS}/docker"
ASSETS_COMPOSE_FILE="${ASSETS_DOCKER_DIR}/compose.assets.yml"

# Correct internal path for assets
ASSETS_ROOT="/usr/src/ptekwpdev/assets"

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage:
  assets_add.sh plugin <slug> <version> <file.zip>
  assets_add.sh theme  <slug> <version> <file.zip>
EOF
}

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

ensure_container_running() {
  if ! docker ps --format '{{.Names}}' | grep -q "^${ASSETS_CONTAINER}\$"; then
    info "Starting assets container: ${ASSETS_CONTAINER}"
    docker compose -f "${ASSETS_COMPOSE_FILE}" up -d
  fi
}

resolve_source_file() {
  local provided="$1"

  if [[ -z "$provided" ]]; then
    error "A source ZIP file must be provided."
    exit 1
  fi

  # Normalize to absolute path
  local abs
  abs="$(cd "$(dirname "$provided")" 2>/dev/null && pwd)/$(basename "$provided")"

  if [[ ! -f "$abs" ]]; then
    error "Source file does not exist: $abs"
    exit 1
  fi

  echo "$abs"
}

copy_asset() {
  local type="$1"
  local slug="$2"
  local version="$3"
  local src_file="$4"

  ensure_container_running

  local dest="${ASSETS_ROOT}/${type}s/${slug}/${version}"

  info "Creating destination directory: ${dest}"
  docker exec "${ASSETS_CONTAINER}" mkdir -p "${dest}"

  info "Copying ZIP file → ${dest}"
  docker cp "$src_file" "${ASSETS_CONTAINER}:${dest}/"

  success "Asset added: ${type}/${slug}/${version}"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

if [[ $# -ne 4 ]]; then
  usage
  exit 1
fi

TYPE="$1"
SLUG="$2"
VERSION="$3"
SOURCE_FILE="$(resolve_source_file "$4")"

case "$TYPE" in
  plugin|theme)
    copy_asset "$TYPE" "$SLUG" "$VERSION" "$SOURCE_FILE"
    ;;
  *)
    error "Unknown asset type: $TYPE"
    usage
    exit 1
    ;;
esac