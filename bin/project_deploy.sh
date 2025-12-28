#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — Project Deployment Orchestrator
#  Script: project_deploy.sh
#  Location: APP_BASE/bin/project_deploy.sh
#
#  Description:
#    Canonical orchestrator for project-level deployment actions.
#    Supports deploy, start, stop, and restart operations for a single project.
#
#    This script loads:
#      - app-level configuration (app_config.sh)
#      - project-level configuration (project_config.sh)
#
#    It operates on the generated project config file:
#      CONFIG_BASE/config/projects.json
#
#  Contract:
#    - Must be executed, not sourced
#    - Never modifies caller's working directory
#    - Never exports environment variables
#    - Never leaks config outside this process
#    - Fails loudly if bootstrap or app_deploy has not been run
# ==============================================================================

set -euo pipefail

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT=""
WHAT_IF=false
ACTION=""

# ==============================================================================
# Load app-level configuration
# ==============================================================================
APP_CONFIG="$APP_BASE/lib/app_config.sh"
if [[ ! -f "$APP_CONFIG" ]]; then
  echo "ERROR: Missing app_config.sh at $APP_CONFIG"
  exit 1
fi

# shellcheck source=/dev/null
source "$APP_CONFIG"

CONFIG_BASE="$(appcfg config_base)"
PROJECTS_FILE="$CONFIG_BASE/config/projects.json"

LOGFILE="$APP_BASE/logs/project_deploy.log"

# Load helpers
source "$APP_BASE/lib/output.sh"
source "$APP_BASE/lib/helpers.sh"

# Load project-level config loader
PROJECT_CONFIG="$APP_BASE/lib/project_config.sh"
if [[ ! -f "$PROJECT_CONFIG" ]]; then
  error "Missing project_config.sh at $PROJECT_CONFIG"
  exit 1
fi

# shellcheck source=/dev/null
source "$PROJECT_CONFIG"

# ==============================================================================
# Argument Parsing
# ==============================================================================
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -p, --project <key>     Project key to deploy (required)
  -a, --action <action>   Action: deploy | start | stop | restart
  -w, --what-if           Dry-run mode (no changes made)
  -h, --help              Show this help message

Examples:
  $(basename "$0") --project demo --action deploy
  $(basename "$0") -p demo -a start
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project)
      PROJECT="$2"
      shift 2
      ;;
    -a|--action)
      ACTION="$2"
      shift 2
      ;;
    -w|--what-if)
      WHAT_IF=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT" ]]; then
  error "Missing required --project <key>"
  usage
  exit 1
fi

if [[ -z "$ACTION" ]]; then
  error "Missing required --action <deploy|start|stop|restart>"
  usage
  exit 1
fi

case "$ACTION" in
  deploy|start|stop|restart) ;;
  *)
    error "Invalid action: $ACTION"
    usage
    exit 1
    ;;
esac

info "Project: $PROJECT"
info "Action:  $ACTION"
$WHAT_IF && info "Mode:    WHAT-IF (dry run)"

# ==============================================================================
# Load project configuration
# ==============================================================================
info "Loading project configuration for '$PROJECT'"

if [[ ! -f "$PROJECTS_FILE" ]]; then
  error "Missing projects.json at: $PROJECTS_FILE"
  exit 1
fi

project_config_load "$PROJECT"

PROJECT_REPO="$(prcfg project_repo)"
PROJECT_DOMAIN="$(prcfg project_domain)"
PROJECT_NETWORK="$(prcfg project_network)"

if [[ -z "$PROJECT_REPO" ]]; then
  error "project_repo not resolved for project '$PROJECT'"
  exit 1
fi

info "Resolved project repo: $PROJECT_REPO"

if $WHAT_IF; then
  whatif "Would operate on project repo: $PROJECT_REPO"
fi

# ==============================================================================
# Directory Scaffolding
# ==============================================================================
scaffold_directories() {
  info "Scaffolding project directories"

  local dirs=(
    "$PROJECT_REPO"
    "$PROJECT_REPO/docker"
    "$PROJECT_REPO/config"
    "$PROJECT_REPO/config/proxy"
    "$PROJECT_REPO/config/wordpress"
    "$PROJECT_REPO/src"
    "$PROJECT_REPO/src/plugins"
    "$PROJECT_REPO/src/themes"
    "$PROJECT_REPO/logs"
  )

  for d in "${dirs[@]}"; do
    if $WHAT_IF; then
      whatif "Would create directory: $d"
    else
      mkdir -p "$d"
    fi
  done
}

# ==============================================================================
# Generate .env from template
# ==============================================================================
generate_env_file() {
  local tpl="$APP_BASE/config/docker/env.project.tpl"
  local out="$PROJECT_REPO/.env"

  info "Generating .env → $out"

  if [[ ! -f "$tpl" ]]; then
    error "Missing env.project.tpl at $tpl"
    exit 1
  fi

  if $WHAT_IF; then
    whatif "Would generate $out from $tpl"
    return
  fi

  sed \
    -e "s|{{project_key}}|$PROJECT|g" \
    -e "s|{{project_domain}}|$PROJECT_DOMAIN|g" \
    -e "s|{{project_network}}|$PROJECT_NETWORK|g" \
    "$tpl" > "$out"

  success ".env created"
}

# ==============================================================================
# Generate compose.project.yml
# ==============================================================================
generate_compose_file() {
  local tpl="$APP_BASE/config/docker/compose.project.yml"
  local out="$PROJECT_REPO/docker/compose.project.yml"

  info "Generating compose.project.yml → $out"

  if [[ ! -f "$tpl" ]]; then
    error "Missing compose.project.yml at $tpl"
    exit 1
  fi

  if $WHAT_IF; then
    whatif "Would generate $out from $tpl"
    return
  fi

  sed \
    -e "s|{{project_key}}|$PROJECT|g" \
    -e "s|{{project_domain}}|$PROJECT_DOMAIN|g" \
    -e "s|{{project_network}}|$PROJECT_NETWORK|g" \
    "$tpl" > "$out"

  success "compose.project.yml created"
}

copy_docker_templates() {
  local src="$CONFIG_BASE/docker"
  local dst="$PROJECT_REPO/docker"

  info "Copying Docker engine templates"

  if [[ ! -d "$src" ]]; then
    error "Missing Docker templates at $src"
    exit 1
  fi

  if $WHAT_IF; then
    whatif "Would copy $src/* → $dst/"
    return
  fi

  mkdir -p "$dst"
  cp -R "$src/"* "$dst/"

  success "Docker templates copied"
}

# ==============================================================================
# Actions
# ==============================================================================
action_deploy() {
  scaffold_directories
  copy_docker_templates
  copy_proxy_templates
  copy_wordpress_templates
  generate_env_file
  generate_compose_file
  success "Project '$PROJECT' deployed"
}

action_start() {
  info "Starting project containers"
  if $WHAT_IF; then
    whatif "Would run: docker compose -f $PROJECT_REPO/compose.project.yml up -d"
  else
    docker compose -f "$PROJECT_REPO/compose.project.yml" up -d
  fi
  success "Project '$PROJECT' started"
}

action_stop() {
  info "Stopping project containers"
  if $WHAT_IF; then
    whatif "Would run: docker compose -f $PROJECT_REPO/compose.project.yml down"
  else
    docker compose -f "$PROJECT_REPO/compose.project.yml" down
  fi
  success "Project '$PROJECT' stopped"
}

action_restart() {
  action_stop
  action_start
}

# ==============================================================================
# Dispatch
# ==============================================================================
case "$ACTION" in
  deploy)   action_deploy ;;
  start)    action_start ;;
  stop)     action_stop ;;
  restart)  action_restart ;;
esac

exit 0