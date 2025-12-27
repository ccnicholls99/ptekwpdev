#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — List Assets in Shared Assets Container
#  Script: assets_list.sh
#  Synopsis:
#    List versioned plugins and themes stored inside the shared assets container.
#
#  Description:
#    This script ensures the assets container is running and then lists all
#    versioned assets under the configured assets root path inside the container.
#    Output is deterministic and contributor-safe.
#
#  Notes:
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
set_log --truncate "$(appcfg app_log_dir)/assets_list.log" \
  "=== Assets List Run ($(date)) ==="

# ------------------------------------------------------------------------------
# Resolve config values
# ------------------------------------------------------------------------------

ASSETS_CONTAINER="$(appcfg assets_container)"
ASSETS_ROOT="$(appcfg assets_root)"

ASSETS_DOCKER_DIR="$(appcfg app_assets_dir)/docker"
ASSETS_COMPOSE_FILE="${ASSETS_DOCKER_DIR}/compose.assets.yml"

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

ensure_container_running() {
  if ! docker ps --format '{{.Names}}' | grep -q "^${ASSETS_CONTAINER}\$"; then
    info "Starting assets container: ${ASSETS_CONTAINER}"
    docker compose -f "${ASSETS_COMPOSE_FILE}" up -d
  fi
}

list_assets() {
  info "Listing assets inside container"

  docker exec "${ASSETS_CONTAINER}" sh -c "
    echo 'Plugins:'
    if [ -d ${ASSETS_ROOT}/plugins ]; then
      find ${ASSETS_ROOT}/plugins -mindepth 2 -maxdepth 2 -type d \
        | sed 's|${ASSETS_ROOT}/plugins/||'
    else
      echo '  (none)'
    fi

    echo ''
    echo 'Themes:'
    if [ -d ${ASSETS_ROOT}/themes ]; then
      find ${ASSETS_ROOT}/themes -mindepth 2 -maxdepth 2 -type d \
        | sed 's|${ASSETS_ROOT}/themes/||'
    else
      echo '  (none)'
    fi
  "
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

info "Ensuring assets container is running"
ensure_container_running

info "Collecting asset list"
list_assets

success "Asset listing complete."