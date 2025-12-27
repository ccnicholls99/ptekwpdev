#!/usr/bin/env bash
# ================================================================================
# PTEKWPDEV — a multi-project, bootstrap app for localized WordPress development
# github: https://github.com/ccnicholls99/ptekwpdev.git
# ------------------------------------------------------------------------------
# Script: project_launch.sh
# Synopsis:
#   Runtime orchestration for project containers
#
# Description:
#   Handles up, down, status, logs, and refresh actions for project Docker stack
#
# Notes:
#   Executed from APP_BASE/bin/project_launch.sh
#   Reads project config from environments.json
#   Pre-Req: APP_BASE/bin/project_deploy.sh
#
# ================================================================================
set -euo pipefail

# ------------------------------------------------------------
# Insert canonical script header (line 2)
# ------------------------------------------------------------
APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ------------------------------------------------------------
# Load logging + helpers
# ------------------------------------------------------------
source "${APP_BASE}/lib/output.sh"
source "${APP_BASE}/lib/helpers.sh"

CONFIG_BASE="${HOME}/.ptekwpdev"
ENVIRONMENTS_JSON="${CONFIG_BASE}/environments.json"

PROJECT_KEY=""
ACTION=""
WHAT_IF=false

usage() {
  echo "Usage: $0 -p <project> -a <action>"
  echo ""
  echo "Actions:"
  echo "  up        Start containers"
  echo "  down      Stop and remove containers"
  echo "  status    Show container status"
  echo "  logs      Show logs"
  echo "  refresh   Restart stack (down → up)"
  echo ""
  echo "Options:"
  echo "  -p, --project <key>   Project key from environments.json"
  echo "  -a, --action <action> One of: up, down, status, logs, refresh"
  echo "  -w, --what-if         Dry run"
  echo "  -h, --help            Show help"
  exit 1
}

# ------------------------------------------------------------
# Parse args
# ------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project) PROJECT_KEY="$2"; shift 2 ;;
    -a|--action)  ACTION="$2"; shift 2 ;;
    -w|--what-if) WHAT_IF=true; shift ;;
    -h|--help)    usage ;;
    *)            error "Unknown option: $1"; usage ;;
  esac
done

if [[ -z "$PROJECT_KEY" ]]; then
  error "Missing required --project option"
  usage
fi

if [[ -z "$ACTION" ]]; then
  error "Missing required --action option"
  usage
fi

# ------------------------------------------------------------
# Load project config
# ------------------------------------------------------------
info "Loading configuration for project: $PROJECT_KEY"

# ------------------------------------------------------------
# Load project config
# ------------------------------------------------------------
info "Loading configuration for project: $PROJECT_KEY"

if [[ ! -f "$ENVIRONMENTS_JSON" ]]; then
  error "environments.json not found at $ENVIRONMENTS_JSON"
  exit 1
fi

# Global app project base
GLOBAL_PROJECT_BASE=$(jq -r '.app.project_base' "$ENVIRONMENTS_JSON")

if [[ -z "$GLOBAL_PROJECT_BASE" || "$GLOBAL_PROJECT_BASE" == "null" ]]; then
  error "Missing app.project_base in $ENVIRONMENTS_JSON"
  exit 1
fi

# Per-project base_dir
PROJECT_BASE_DIR=$(jq -r --arg p "$PROJECT_KEY" '.environments[$p].base_dir' "$ENVIRONMENTS_JSON")

if [[ -z "$PROJECT_BASE_DIR" || "$PROJECT_BASE_DIR" == "null" ]]; then
  error "Missing environments[\"$PROJECT_KEY\"].base_dir in $ENVIRONMENTS_JSON"
  exit 1
fi

PROJECT_BASE="${GLOBAL_PROJECT_BASE}/${PROJECT_BASE_DIR}"

info "Resolved PROJECT_BASE: $PROJECT_BASE"

# ------------------------------------------------------------
# Initialize project logging
# ------------------------------------------------------------
LOG_DIR="${PROJECT_BASE}/app/logs"
mkdir -p "$LOG_DIR"

set_log --truncate "${LOG_DIR}/launch.log" "+--- Project Launch Begins ---+"

success "Logging initialized at ${LOG_DIR}/launch.log"

# ------------------------------------------------------------
# Docker compose file
# ------------------------------------------------------------
COMPOSE_FILE="${APP_BASE}/docker/compose.project.yml"

run_or_preview() {
  local msg="$1"
  shift
  if $WHAT_IF; then
    warn "[WHAT-IF] $msg"
    warn "[WHAT-IF] Command: $*"
  else
    info "$msg"
    "$@"
  fi
}

# ------------------------------------------------------------
# Action handlers
# ------------------------------------------------------------
case "$ACTION" in

  up)
    run_or_preview "Starting project containers" \
      docker compose -f "$COMPOSE_FILE" up -d
    ;;

  down)
    run_or_preview "Stopping project containers" \
      docker compose -f "$COMPOSE_FILE" down
    ;;

  status)
    run_or_preview "Showing container status" \
      docker compose -f "$COMPOSE_FILE" ps
    ;;

  logs)
    run_or_preview "Showing container logs" \
      docker compose -f "$COMPOSE_FILE" logs -f
    ;;

  refresh)
    run_or_preview "Refreshing project containers (down → up)" \
      docker compose -f "$COMPOSE_FILE" down
    run_or_preview "Starting containers" \
      docker compose -f "$COMPOSE_FILE" up -d
    ;;

  *)
    error "Unknown action: $ACTION"
    usage
    ;;
esac

success "Action '$ACTION' completed for project '$PROJECT_KEY'"