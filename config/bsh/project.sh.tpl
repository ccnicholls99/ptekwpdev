#!/usr/bin/env bash
#
# Project dev environment control script
# Template: app_base/config/bsh/project.sh.tpl
#
# Usage:
#   ./project.sh start   # start project containers
#   ./project.sh stop    # stop project containers
#   ./project.sh restart # restart project containers
#   ./project.sh status  # show container status

set -euo pipefail

PROJECT_NAME="${PROJECT_NAME:-example}"
PROJECT_BASE="${HOME}/.ptekwpdev/projects/${PROJECT_NAME}"
LOG_FILE="${PROJECT_BASE}/logs/project.log"

# --- Logging helpers ---
log_header() {
  local action="$1"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  {
    echo ""
    echo "=================================================="
    echo ">>> ${PROJECT_NAME} ${action} run at ${timestamp}"
    echo "=================================================="
    echo ""
  } >> "$LOG_FILE"
}

info() {
  echo "[INFO] $*" | tee -a "$LOG_FILE"
}

error() {
  echo "[ERROR] $*" | tee -a "$LOG_FILE" >&2
}

# --- Actions ---
start_project() {
  log_header "START"
  info "Starting project ${PROJECT_NAME} containers..."
  docker compose -f "${PROJECT_BASE}/docker/compose.project.yml" up -d
  info "Project ${PROJECT_NAME} started."
}

stop_project() {
  log_header "STOP"
  info "Stopping project ${PROJECT_NAME} containers..."
  docker compose -f "${PROJECT_BASE}/docker/compose.project.yml" down
  info "Project ${PROJECT_NAME} stopped."
}

restart_project() {
  log_header "RESTART"
  info "Restarting project ${PROJECT_NAME} containers..."
  stop_project
  start_project
}

status_project() {
  info "Showing status for project ${PROJECT_NAME} containers..."
  docker compose -f "${PROJECT_BASE}/docker/compose.project.yml" ps
}

# --- Main ---
case "${1:-}" in
  start)   start_project ;;
  stop)    stop_project ;;
  restart) restart_project ;;
  status)  status_project ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac