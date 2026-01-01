#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — Assets Bootstrap Script
#  Script: assets_bootstrap.sh
#  Synopsis:
#    Build and initialize the shared assets container and prepare the
#    versioned assets directory structure.
#
#  Description:
#    This script builds the assets container image, ensures the container is
#    running, and prepares the directory structure inside the container for
#    versioned plugins and themes.
#
#  Notes:
#    - Must be executed from PTEK_APP_BASE/bin
#    - Uses in-memory config dictionary PTEKWPCFG
#    - Uses appcfg() helper for config access
#    - Uses Option C logging
#    - Never exports environment variables
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
# Resolve APP_BASE as the parent directory of this script's directory
PTEK_APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/app_config.sh"

#echo "LOGDIR=$(appcfg app_log_dir)"
#echo "CONTAINER=$(appcfg assets_container)"
#echo "ROOT=$(appcfg assets_root)"

# Major script → initialize its own logfile
set_log --truncate "$(appcfg app_log_dir)/assets_bootstrap.log" \
  "=== Assets Bootstrap Run ($(date)) ==="

# ------------------------------------------------------------------------------
# Resolve config values
# ------------------------------------------------------------------------------

ASSETS_CONTAINER="$(appcfg assets_container)"
ASSETS_ROOT="$(appcfg assets_root)"

ASSETS_DOCKER_DIR="$(appcfg app_assets_dir)/docker"
ASSETS_COMPOSE_FILE="${ASSETS_DOCKER_DIR}/compose.assets.yml"
ASSETS_DOCKERFILE="${ASSETS_DOCKER_DIR}/Dockerfile"

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: $(basename "$0") <action>

Actions:
  build     Build the assets container image
  up        Start the assets container
  init      Initialize the internal assets directory structure
  full      Run build + up + init

Examples:
  assets_bootstrap.sh build
  assets_bootstrap.sh up
  assets_bootstrap.sh init
  assets_bootstrap.sh full
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

init_assets_structure() {
  ensure_container_running

  info "Initializing assets directory structure inside container"

  docker exec "${ASSETS_CONTAINER}" mkdir -p \
    "${ASSETS_ROOT}/plugins" \
    "${ASSETS_ROOT}/themes"

  success "Assets directory initialized at: ${ASSETS_ROOT}"
}

action_build() {
  info "Building assets container image using: ${ASSETS_DOCKERFILE}"
  docker build -t "${ASSETS_CONTAINER}" -f "${ASSETS_DOCKERFILE}" "${ASSETS_DOCKER_DIR}"
  success "Assets container image built: ${ASSETS_CONTAINER}"
}

action_up() {
  info "Starting assets container"
  docker compose -f "${ASSETS_COMPOSE_FILE}" up -d
  success "Assets container is running: ${ASSETS_CONTAINER}"
}

action_init() {
  init_assets_structure
}

action_full() {
  action_build
  action_up
  action_init
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

ACTION="$1"

case "$ACTION" in
  build) action_build ;;
  up)    action_up ;;
  init)  action_init ;;
  full)  action_full ;;
  -h|--help) usage ;;
  *)
    error "Unknown action: $ACTION"
    usage
    exit 1
    ;;
esac