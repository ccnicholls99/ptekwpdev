#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — List Assets in Shared Assets Container
#  Script: assets_list.sh
#  Synopsis:
#    List versioned plugins and themes stored inside the ptekwpdev_assets
#    container.
#
#  Description:
#    This script ensures the assets container is running and then lists all
#    versioned assets under /usr/src/ptekwpdev/assets inside the container.
#    Output is human-readable and deterministic.
#
#  Usage:
#    assets_list.sh
#
#  Notes:
#    - Must be executed from PTEK_APP_BASE/bin
#    - All environment variables are PTEK_-namespaced
#    - Logging utilities come from lib/output.sh
#    - Caller directory is always restored on exit
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

# Major script → initialize its own logfile
set_log --truncate "${PTEK_APP_LOG_DIR}/assets_list.log" \
  "=== Assets List Run ($(date)) ==="

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------

ASSETS_CONTAINER="ptekwpdev_assets"
ASSETS_DOCKER_DIR="${PTEK_APP_ASSETS}/docker"
ASSETS_COMPOSE_FILE="${ASSETS_DOCKER_DIR}/compose.assets.yml"

# Correct internal path for assets
ASSETS_ROOT="/usr/src/ptekwpdev/assets"

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
      find ${ASSETS_ROOT}/plugins -mindepth 3 -maxdepth 3 -type d \
        | sed 's|${ASSETS_ROOT}/plugins/||'
    else
      echo '  (none)'
    fi

    echo ''
    echo 'Themes:'
    if [ -d ${ASSETS_ROOT}/themes ]; then
      find ${ASSETS_ROOT}/themes -mindepth 3 -maxdepth 3 -type d \
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