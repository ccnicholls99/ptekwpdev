#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — App Deployment Script
#  Script: app_deploy.sh
#  Synopsis:
#    Deploy the app-level runtime environment by generating environments.json
#    from the existing template, copying runtime config templates into
#    CONFIG_BASE, generating the app-level .env file, and starting core
#    containers.
#
#  Description:
#    This script uses the static app-level configuration stored in app.json
#    (loaded via app_config.sh) and the runtime template stored in
#    APP_BASE/config/environments.tpl.json to generate the runtime
#    environments.json file. It then deploys Docker engine templates,
#    generates the .env file, and starts the core containers.
#
#  Notes:
#    - Must be executed from PTEK_APP_BASE/bin
#    - Uses PTEKWPCFG + appcfg() for all app-level settings
#    - environments.json contains ONLY runtime + project-level settings
#    - No app-level secrets or constants are written to environments.json
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

# Major script → initialize its own logfile
set_log --truncate "$(appcfg app_log_dir)/app_deploy.log" \
  "=== App Deploy Run ($(date)) ==="

# ------------------------------------------------------------------------------
# Resolve config values
# ------------------------------------------------------------------------------

CONFIG_BASE="$(appcfg config_base)"
DOCKER_SRC_DIR="${APP_BASE}/config/docker"
DOCKER_DST_DIR="${CONFIG_BASE}/docker"

ENV_TPL="${APP_BASE}/config/environments.tpl.json"
ENV_OUT="${CONFIG_BASE}/environments.json"

WHAT_IF=false
ACTION=""

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: app_deploy.sh -a {init|up|down|reset} [-w]

Actions:
  init   Generate environments.json, deploy templates, generate .env, start containers
  up     Start containers only
  down   Stop containers
  reset  Stop containers and remove volumes
EOF
}

# ------------------------------------------------------------------------------
# Parse flags
# ------------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -w|--what-if) WHAT_IF=true; shift ;;
    -a|--action) ACTION="$2"; shift 2 ;;
    *) error "Unknown option: $1"; exit 1 ;;
  esac
done

# ------------------------------------------------------------------------------
# Generate environments.json from template
# ------------------------------------------------------------------------------

generate_environments_json() {
  info "Generating environments.json → ${ENV_OUT}"

  if [[ ! -f "$ENV_TPL" ]]; then
    error "Missing template: ${ENV_TPL}"
    exit 1
  fi

  if $WHAT_IF; then
    whatif "Would generate ${ENV_OUT} from ${ENV_TPL}"
    return
  fi

  # Copy template as-is
  cp "${ENV_TPL}" "${ENV_OUT}"

  # Validate JSON
  if ! jq empty "${ENV_OUT}" >/dev/null 2>&1; then
    error "Generated environments.json is invalid JSON"
    exit 1
  fi

  success "environments.json created"
}

# ------------------------------------------------------------------------------
# Deploy Docker templates
# ------------------------------------------------------------------------------

deploy_docker_templates() {
  info "Deploying Docker engine templates → ${DOCKER_DST_DIR}"

  mkdir -p "${DOCKER_DST_DIR}"

  local assets=(
    "compose.app.yml"
    "Dockerfile.wordpress"
    "Dockerfile.wpcli"
    "env.app.tpl"
  )

  for file in "${assets[@]}"; do
    local src="${DOCKER_SRC_DIR}/${file}"
    local dst="${DOCKER_DST_DIR}/${file}"

    if [[ ! -f "$src" ]]; then
      warn "Missing docker template: $file"
      continue
    fi

    if $WHAT_IF; then
      whatif "Would copy $src → $dst"
    else
      cp "$src" "$dst"
      info "Copied $src → $dst"
    fi
  done

  success "Docker templates deployed"
}

# ------------------------------------------------------------------------------
# Generate .env from env.app.tpl
# ------------------------------------------------------------------------------

generate_env_file() {
  local tpl="${DOCKER_DST_DIR}/env.app.tpl"
  local env_file="${DOCKER_DST_DIR}/.env"

  if [[ ! -f "$tpl" ]]; then
    if $WHAT_IF; then
      whatif "Would generate .env from ${tpl}, but template is not present in what-if mode"
      return
    fi
    error "Missing template: $tpl"
    exit 1
  fi

  info "Generating app-level .env file..."

  : > "$env_file"

  while IFS= read -r line; do
    # Replace {{key}} with values from PTEKWPCFG
    for key in "${!PTEKWPCFG[@]}"; do
      val="${PTEKWPCFG[$key]}"
      safe_val=$(printf '%s\n' "$val" | sed 's/[&/\]/\\&/g')
      line=$(echo "$line" | sed "s|{{${key}}}|${safe_val}|g")
    done
    echo "$line" >> "$env_file"
  done < "$tpl"

  success ".env file written to ${env_file}"
}

# ------------------------------------------------------------------------------
# Start core containers
# ------------------------------------------------------------------------------

start_containers() {
  if $WHAT_IF; then
    whatif "Would start core containers"
    return
  fi

  info "Starting core containers..."

  docker compose -f "${DOCKER_DST_DIR}/compose.app.yml" \
    --env-file "${DOCKER_DST_DIR}/.env" up -d

  success "Core containers are online"
}

# ------------------------------------------------------------------------------
# Stop containers
# ------------------------------------------------------------------------------

stop_containers() {
  docker compose -f "${DOCKER_DST_DIR}/compose.app.yml" \
    --env-file "${DOCKER_DST_DIR}/.env" down
}

reset_containers() {
  docker compose -f "${DOCKER_DST_DIR}/compose.app.yml" \
    --env-file "${DOCKER_DST_DIR}/.env" down -v
}

# ------------------------------------------------------------------------------
# Dispatcher
# ------------------------------------------------------------------------------

case "${ACTION:-}" in
  init)
    generate_environments_json
    deploy_docker_templates
    generate_env_file
    start_containers

    success "App environment deployed at ${CONFIG_BASE}"
    ;;
  up)
    start_containers
    ;;
  down)
    stop_containers
    ;;
  reset)
    reset_containers
    ;;
  *)
    error "Unknown or missing action: $ACTION"
    usage
    exit 1
    ;;
esac