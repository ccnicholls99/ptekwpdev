#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — Add Asset to Shared Assets Container
#  Script: assets_add.sh
#  Synopsis:
#    Add a plugin or theme (ZIP file) into the versioned assets repository
#    inside the ptekwpdev_assets container.
#
#  Description:
#    This script copies a ZIP file representing a plugin or theme into the
#    versioned assets directory inside the shared assets container. It ensures
#    the container is running, validates the source file, and performs a
#    deterministic copy.
#
#  Usage:
#    assets_add.sh plugin <slug> <version> <file.zip>
#    assets_add.sh theme  <slug> <version> <file.zip>
#
#  Notes:
#    - Source MUST be a direct file path (ZIP file)
#    - Must be executed from PTEK_APP_BASE/bin
#    - Uses in-memory config dictionary PTEKWPCFG
#    - Uses appcfg() helper for config access
#    - Uses Option C logging
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail

# ------------------------------------------------------------------------------
# Preserve caller directory
# ------------------------------------------------------------------------------

PTEK_CALLER_PWD="$(pwd)"
ptekwp_cleanup() {
  cd "$PTEK_CALLER_PWD" || true
}
trap ptekwp_cleanup EXIT

# ------------------------------------------------------------------------------
# Load app config + logging
# ------------------------------------------------------------------------------

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/app_config.sh"

# Major script → initialize its own logfile
set_log --truncate "$(appcfg app_log_dir)/assets_add.log" \
  "=== Assets Add Run ($(date)) ==="

# ------------------------------------------------------------------------------
# Resolve config values
# ------------------------------------------------------------------------------

ASSETS_CONTAINER="$(appcfg assets_container)"
ASSETS_ROOT="$(appcfg assets_root)"

ASSETS_DOCKER_DIR="$(appcfg app_assets_dir)/docker"
ASSETS_COMPOSE_FILE="${ASSETS_DOCKER_DIR}/compose.assets.yml"

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage:
  assets_add.sh plugin <slug> <version> <file.zip>
  assets_add.sh theme  <slug> <version> <file.zip>

Examples:
  assets_add.sh plugin breakdance 2.5.2 /path/to/breakdance-2.5.2.zip
  assets_add.sh theme twentytwentyfive 1.0 /path/to/theme.zip
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