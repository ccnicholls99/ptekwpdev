#!/usr/bin/env bash
# ====Assets Bootstrap>>=======================================================
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
# ====<<Assets Bootstrap=======================================================

set -o errexit
set -o nounset
set -o pipefail

# Resolve APP_BASE as the parent directory of this script's directory
PTEK_APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PTEK_APP_BASE

# ====Error Handling>>=====================================
# Source Error Handling
# Generated Code, modify with caution
# =========================================================
_ts() { date +"%Y-%m-%d %H:%M:%S"; }
ptek_err() { COLOR_RED="\033[31m"; COLOR_RESET="\033[0m"; echo -e "${COLOR_RED}[$(_ts)] ERROR: $*${COLOR_RESET}" >&2; }

CALLER_PWD="$(pwd)"
trap 'ptek_err "Command failed (exit $?): $BASH_COMMAND"' ERR
trap 'cd "$CALLER_PWD" || true' EXIT
# ====<<Error Handling=====================================

# ====Log Handling>>=======================================
# Source Log Handling
# Set PTEK_LOGFILE before sourcing to set logfile (default=/dev/null)
# Else call set_log [options] <logfile>, post sourcing
# Generated Code, modify with caution
# =========================================================

# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/output.sh"

# ====<<Log Handling=======================================

# ====App Config>>=========================================
# Source App Configuration Library
# Defines PTEKWPCFG settngs dictionary. Adds appcfg 'key' accessor function
# Generated Code, modify with caution
# =========================================================

# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/app_config.sh"

# ====<<App Config=========================================

# Major script → initialize its own logfile
set_log --truncate "$(appcfg app_log_dir)/assets_bootstrap.log" \
  "=== Assets Bootstrap Run ($(date)) ==="

# ------------------------------------------------------------------------------
# Resolve config values
# ------------------------------------------------------------------------------

ASSETS_CONTAINER="$(appcfg assets.container)"
ASSETS_ROOT="$(appcfg assets.root_path)"

ASSETS_DOCKER_DIR="$PTEK_APP_BASE/app/assets/docker"
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
generate_assets_env() {
  local env_file="${ASSETS_DOCKER_DIR}/.env"

  info "Generating assets .env file..."

  cat > "$env_file" <<EOF
# -----------------------------------------------------------------------------
# Asset Configuration: Container Name, Volume Name & volume mount
# -----------------------------------------------------------------------------
ASSETS_CONTAINER=$(appcfg assets.container)
ASSETS_VOLUME=$(appcfg assets.volume_name)
ASSETS_ROOT=$(appcfg assets.root_path)
EOF

  success "Assets .env written to: $env_file"
}

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
  generate_assets_env
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
  -h|--help) usage; exit 0 ;;
  *)
    error "Unknown action: $ACTION"
    usage
    exit 1
    ;;
esac

exit 0