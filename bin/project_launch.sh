#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — Project Launch Script
#  Script: project_launch.sh
#  Synopsis:
#    Manage Docker lifecycle actions for a single project.
#
#  Description:
#    This script loads project configuration from CONFIG_BASE/config/projects.json,
#    resolves the project repo, and performs runtime Docker actions such as
#    start, stop, restart, status, logs, and refresh.
#
#  Notes:
#    - Must be executed from APP_BASE/bin
#    - Reads ONLY from CONFIG_BASE
#    - Never performs provisioning (that is project_deploy.sh)
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

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "${APP_BASE}/lib/app_config.sh"
source "${APP_BASE}/lib/output.sh"
source "${APP_BASE}/lib/helpers.sh"
source "${APP_BASE}/lib/project_config.sh"

set_log --truncate "$(appcfg app_log_dir)/project_launch.log" \
  "=== Project Launch Run ($(date)) ==="

# ------------------------------------------------------------------------------
# Resolve config values
# ------------------------------------------------------------------------------

CONFIG_BASE="$(appcfg config_base)"
PROJECT_BASE="$(appcfg project_base)"

CONFIG_CONFIG_DIR="${CONFIG_BASE}/config"

PROJECT=""
ACTION=""
WHAT_IF=false

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: project_launch.sh -p <project_key> -a {start|stop|restart|status|logs|refresh} [-w]

Actions:
  start     Start project containers
  stop      Stop project containers
  restart   Stop then start project containers
  status    Show container status
  logs      Show container logs
  refresh   Down + Up (safe refresh)
EOF
}

# ------------------------------------------------------------------------------
# Parse flags
# ------------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project) PROJECT="$2"; shift 2 ;;
    -a|--action) ACTION="$2"; shift 2 ;;
    -w|--what-if) WHAT_IF=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "${PROJECT:-}" ]]; then
  error "Missing required --project <key>"
  usage
  exit 1
fi

if [[ -z "${ACTION:-}" ]]; then
  error "Missing required --action"
  usage
  exit 1
fi

# ------------------------------------------------------------------------------
# Load project configuration
# ------------------------------------------------------------------------------

PROJECTS_FILE="${CONFIG_CONFIG_DIR}/projects.json"

if [[ ! -f "$PROJECTS_FILE" ]]; then
  error "Missing projects.json at ${PROJECTS_FILE}"
  exit 1
fi

project_config_load "$PROJECT"

PROJECT_REPO="$(prcfg project_repo)"

if [[ -z "$PROJECT_REPO" ]]; then
  error "project_repo not resolved for project '${PROJECT}'"
  exit 1
fi

COMPOSE_FILE="${PROJECT_REPO}/docker/compose.project.yml"
ENV_FILE="${PROJECT_REPO}/docker/.env"

# ------------------------------------------------------------------------------
# Validate runtime files
# ------------------------------------------------------------------------------

validate_runtime() {
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    error "Missing compose.project.yml at ${COMPOSE_FILE}"
    exit 1
  fi

  if [[ ! -f "$ENV_FILE" ]]; then
    error "Missing .env at ${ENV_FILE}"
    exit 1
  fi
}

# ------------------------------------------------------------------------------
# Docker actions
# ------------------------------------------------------------------------------

start_containers() {
  validate_runtime

  if $WHAT_IF; then
    whatif "Would start containers for project '${PROJECT}'"
    return
  fi

  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
  success "Project containers started"
}

stop_containers() {
  validate_runtime

  if $WHAT_IF; then
    whatif "Would stop containers for project '${PROJECT}'"
    return
  fi

  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down
  success "Project containers stopped"
}

restart_containers() {
  stop_containers
  start_containers
}

status_containers() {
  validate_runtime

  if $WHAT_IF; then
    whatif "Would show status for project '${PROJECT}'"
    return
  fi

  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps
}

logs_containers() {
  validate_runtime

  if $WHAT_IF; then
    whatif "Would show logs for project '${PROJECT}'"
    return
  fi

  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs -f
}

refresh_containers() {
  validate_runtime

  if $WHAT_IF; then
    whatif "Would refresh containers (down + up) for project '${PROJECT}'"
    return
  fi

  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d

  success "Project containers refreshed"
}

# ------------------------------------------------------------------------------
# Dispatcher
# ------------------------------------------------------------------------------

case "${ACTION}" in
  start)   start_containers ;;
  stop)    stop_containers ;;
  restart) restart_containers ;;
  status)  status_containers ;;
  logs)    logs_containers ;;
  refresh) refresh_containers ;;
  *)
    error "Unknown action: ${ACTION}"
    usage
    exit 1
    ;;
esac

exit 0