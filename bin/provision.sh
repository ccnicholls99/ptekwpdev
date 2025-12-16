#!/usr/bin/env bash
#
# Provision script for WordPress dev environments (ptekwpdev)
# - Centralized project lookup in ~/.ptekwpdev/environments.json
# - Creates scaffold under PROJECT_BASE (app, bin, docker, src)
# - Shared output functions sourced from APP_BASE/lib/output.sh
#

set -euo pipefail

# -------------------------------
# Path resolution
# -------------------------------
APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# -------------------------------
# Defaults
# -------------------------------
PROJECT=""
CONFIG_BASE="$HOME/.ptekwpdev"
CONFIG_FILE="$CONFIG_BASE/environments.json"
WHATIF=false

# -------------------------------
# Load helpers
# -------------------------------
if [[ -f "$APP_BASE/lib/output.sh" ]]; then
  # shellcheck disable=SC1091
  source "$APP_BASE/lib/output.sh"
else
  echo "Missing output.sh at $APP_BASE/lib/" >&2
  exit 1
fi

if [[ -f "$APP_BASE/lib/helpers.sh" ]]; then
  # shellcheck disable=SC1091
  source "$APP_BASE/lib/helpers.sh"
else
  error "Missing helpers.sh at $APP_BASE/lib/"
  exit 1
fi
# -------------------------------
# Usage
# -------------------------------
usage() {
  printf "Usage: %s --project NAME [-w|--what-if]\n" "$(basename "$0")"
  printf "\nOptions:\n"
  printf "  -p, --project NAME        REQUIRED project key\n"
  printf "  -w, --what-if             Simulate actions without making changes\n"
  printf "  -h, --help                Show this help message\n"
  printf "\nExample:\n"
  printf "  %s --project demo\n" "$(basename "$0")"
}

# -------------------------------
# Option parsing
# -------------------------------
parse_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--project) PROJECT="$2"; shift 2 ;;
      -w|--what-if) WHATIF=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) error "Unknown option: $1"; usage; exit 1 ;;
    esac
  done
  if [[ -z "$PROJECT" ]]; then
    error "--project is required"
    usage
    exit 1
  fi
}

# -------------------------------
# Require project
# -------------------------------
resolve_project() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    error "No project config found at $CONFIG_FILE"
    exit 1
  fi

  APP_PROJECT_BASE=$(jq -r '.app.project_base' "$CONFIG_FILE" | sed "s|\$HOME|$HOME|")
  PROJECT_CONFIG=$(jq -r --arg pr "$PROJECT" '.environments[$pr]' "$CONFIG_FILE")

  HOST_DOMAIN=$(echo "$PROJECT_CONFIG" | jq -r '.domain // empty')
  BASE_DIR_REL=$(echo "$PROJECT_CONFIG" | jq -r '.base_dir // empty' | sed 's|^/||')

  PROJECT_BASE="$APP_PROJECT_BASE/$BASE_DIR_REL"

  if [[ -z "$BASE_DIR_REL" || -z "$HOST_DOMAIN" ]]; then
    error "Project '$PROJECT' missing base_dir or domain in $CONFIG_FILE"
    exit 1
  fi

  LOG_DIR="$PROJECT_BASE/app/logs"
  ensure_dir "$LOG_DIR"
  LOG_FILE="$LOG_DIR/provision.log"
  exec > >(tee -a "$LOG_FILE") 2>&1

  info "Resolved project: $PROJECT_BASE (domain=$HOST_DOMAIN)"
}


scaffold_directories() {
  if $WHATIF; then
    info "[WHAT-IF] Would create scaffold under $PROJECT_BASE: app, bin, docker, src"
    info "[WHAT-IF] Would create app/config/docker and app/config/nginx"
  else
    ensure_dir "$PROJECT_BASE"
    for dir in app bin docker src; do
      ensure_dir "$PROJECT_BASE/$dir"
    done
    ensure_dir "$PROJECT_BASE/app/config/docker"
    ensure_dir "$PROJECT_BASE/app/config/nginx"
    success "Scaffold created under $PROJECT_BASE"
  fi
}

generate_env_file() {
  ENV_FILE="$PROJECT_BASE/docker/.env"
  TPL_ENV="$APP_BASE/config/docker/env.project.tpl"

  ensure_dir "$(dirname "$ENV_FILE")"
  cp "$TPL_ENV" "$ENV_FILE"

  project_json=$(jq -r --arg pr "$PROJECT" '.environments[$pr]' "$CONFIG_FILE")

  # First pass: non-secrets
  for key in $(echo "$project_json" | jq -r 'keys[]'); do
    [[ "$key" == "secrets" ]] && continue
    val=$(echo "$project_json" | jq -r ".${key}")
    safe_val=$(printf '%s\n' "$val" | sed 's/[&/\]/\\&/g')
    sed -i "s|{{${key}}}|${safe_val}|g" "$ENV_FILE"
  done

  # Second pass: secrets
  secrets_json=$(echo "$project_json" | jq -r '.secrets // empty')
  if [[ -n "$secrets_json" && "$secrets_json" != "null" ]]; then
    for key in $(echo "$secrets_json" | jq -r 'keys[]'); do
      val=$(echo "$secrets_json" | jq -r ".${key}")
      safe_val=$(printf '%s\n' "$val" | sed 's/[&/\]/\\&/g')
      info "Replacing {{${key}}} with [*****]"
      sed -i "s|{{${key}}}|${safe_val}|g" "$ENV_FILE"
    done
  fi
}

generate_compose_file() {
  COMPOSE_TPL="$APP_BASE/config/docker/compose.provision.yml"
  COMPOSE_OUT="$PROJECT_BASE/docker/compose.project.yml"

  ensure_dir "$(dirname "$COMPOSE_OUT")"
  cp "$COMPOSE_TPL" "$COMPOSE_OUT"
  success "Copied compose.provision.yml → $COMPOSE_OUT"
}

provision_project() {
  parse_options "$@"
  resolve_project
  scaffold_directories
  generate_env_file
  generate_compose_file
  success "Provisioning completed for $PROJECT ($HOST_DOMAIN)"
}

provision_project "$@"
