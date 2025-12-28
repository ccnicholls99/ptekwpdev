#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — App Deployment Script
#  Script: app_deploy.sh
#  Synopsis:
#    Deploy the app-level runtime environment by generating projects.json
#    from the existing template, copying runtime config templates into
#    CONFIG_BASE, generating the app-level .env file, and starting core
#    containers.
#
#  Description:
#    This script uses the static app-level configuration stored in app.json
#    (loaded via app_config.sh) and the runtime template stored in
#    APP_BASE/app/config/projects.tpl.json to generate the runtime
#    CONFIG_BASE/config/projects.json file. It then deploys Docker engine
#    templates, container configuration templates, generates the .env file,
#    and starts the core containers.
#
#  Notes:
#    - Must be executed from PTEK_APP_BASE/bin
#    - Uses PTEKWPCFG + appcfg() for all app-level settings
#    - projects.json contains ONLY runtime + project-level settings
#    - No app-level secrets or constants are written to projects.json
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

# Env + container config live under app/config and config/
APP_ENV_CONFIG_DIR="${APP_BASE}/app/config"
CONFIG_CONFIG_DIR="${CONFIG_BASE}/config"

PROJECTS_TPL="$APP_ENV_CONFIG_DIR/projects.tpl.json"
PROJECTS_OUT="$CONFIG_CONFIG_DIR/projects.json"

WHAT_IF=false
ACTION=""

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: app_deploy.sh -a {init|up|down|reset} [-w]

Actions:
  init   Generate projects.json, deploy templates, generate .env, start containers
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
# Generate projects.json from template
# ------------------------------------------------------------------------------

generate_projects_json() {
  info "Generating projects.json → ${PROJECTS_OUT}"

  if [[ ! -f "$PROJECTS_TPL" ]]; then
    error "Missing template: ${PROJECTS_TPL}"
    exit 1
  fi

  if $WHAT_IF; then
    whatif "Would generate ${PROJECTS_OUT} from ${PROJECTS_TPL}"
    return
  fi

  # Ensure output directory exists
  mkdir -p "$(dirname "$PROJECTS_OUT")"

  # Copy template as-is
  cp "${PROJECTS_TPL}" "${PROJECTS_OUT}"

  # Validate JSON
  if ! jq empty "${PROJECTS_OUT}" >/dev/null 2>&1; then
    error "Generated projects.json is invalid JSON"
    exit 1
  fi

  success "projects.json created"
}

# ------------------------------------------------------------------------------
# Initialize demo project in projects.json
# ------------------------------------------------------------------------------

initialize_demo_project() {
  info "Initializing demo project in ${PROJECTS_OUT}"

  if $WHAT_IF; then
    whatif "Would overwrite ${PROJECTS_OUT} with a demo project definition"
    return
  fi

  mkdir -p "$(dirname "$PROJECTS_OUT")"

  jq -n '
    {
      projects: {
        demo: {
          project_domain: "demo.local",
          project_network: "ptekwpdev_demo_net",
          base_dir: "demo",
          wordpress: {
            image: "wordpress:latest",
            host: "demo.local",
            port: 8080,
            ssl_port: 8443
          },
          secrets: {
            sqldb_name: "demo_db",
            sqldb_user: "demo_user",
            sqldb_pass: "demo_pass",
            wp_admin_user: "admin",
            wp_admin_email: "admin@demo.local",
            wp_admin_pass: "password"
          },
          dev_sources: {
            plugins: [],
            themes: []
          }
        }
      }
    }
  ' > "${PROJECTS_OUT}"

  # Validate JSON again
  if ! jq empty "${PROJECTS_OUT}" >/dev/null 2>&1; then
    error "Initialized projects.json is invalid JSON"
    exit 1
  fi

  success "Demo project initialized in projects.json"
}

# ------------------------------------------------------------------------------
# Deploy env templates from APP_BASE/app/config → CONFIG_BASE/config
# ------------------------------------------------------------------------------

deploy_env_templates() {
  info "Deploying env templates from ${APP_ENV_CONFIG_DIR} → ${CONFIG_CONFIG_DIR}"

  if $WHAT_IF; then
    whatif "Would copy ${APP_ENV_CONFIG_DIR}/env.*.tpl → ${CONFIG_CONFIG_DIR}/"
    return
  fi

  mkdir -p "${CONFIG_CONFIG_DIR}"

  # Copy any env.*.tpl (env.app.tpl, env.project.tpl, env.sqladmin.tpl, etc.)
  shopt -s nullglob
  local env_templates=("${APP_ENV_CONFIG_DIR}"/env.*.tpl)
  shopt -u nullglob

  if ((${#env_templates[@]} == 0)); then
    warn "No env.*.tpl templates found in ${APP_ENV_CONFIG_DIR}"
    return
  fi

  for tpl in "${env_templates[@]}"; do
    local base
    base="$(basename "$tpl")"
    cp "$tpl" "${CONFIG_CONFIG_DIR}/${base}"
    info "Copied $tpl → ${CONFIG_CONFIG_DIR}/${base}"
  done

  success "Env templates deployed"
}

# ------------------------------------------------------------------------------
# Deploy Docker templates APP_BASE/config/docker → CONFIG_BASE/docker
# ------------------------------------------------------------------------------

deploy_docker_templates() {
  info "Deploying Docker engine templates → ${DOCKER_DST_DIR}"

  if [[ ! -d "$DOCKER_SRC_DIR" ]]; then
    error "Missing docker template directory: ${DOCKER_SRC_DIR}"
    exit 1
  fi

  mkdir -p "${DOCKER_DST_DIR}"

  local assets=(
    "compose.app.yml"
    "compose.project.yml"
    "Dockerfile.wordpress"
    "Dockerfile.wpcli"
    ".dockerignore"
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
# Deploy container config directories APP_BASE/config → CONFIG_BASE/config
# ------------------------------------------------------------------------------

deploy_container_configs() {
  info "Deploying container config directories from ${APP_BASE}/config → ${CONFIG_CONFIG_DIR}"

  local src="${APP_BASE}/config"
  local dst="${CONFIG_CONFIG_DIR}"

  local dirs=(
    proxy
    wordpress
    sqladmin
    doc
  )

  for d in "${dirs[@]}"; do
    if [[ -d "$src/$d" ]]; then
      if $WHAT_IF; then
        whatif "Would copy $src/$d → $dst/$d"
      else
        mkdir -p "$dst/$d"
        cp -R "$src/$d/"* "$dst/$d/" 2>/dev/null || true
        info "Copied $src/$d → $dst/$d"
      fi
    else
      warn "Container config directory not found: $src/$d"
    fi
  done

  success "Container config directories deployed"
}

# ------------------------------------------------------------------------------
# Generate .env from env.app.tpl (now from CONFIG_BASE/config)
# ------------------------------------------------------------------------------

generate_env_file() {
  local tpl="${CONFIG_CONFIG_DIR}/env.app.tpl"
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
    whatif "Would start core containers using compose.app.yml in ${DOCKER_DST_DIR}"
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
    generate_projects_json
    initialize_demo_project
    deploy_env_templates
    deploy_docker_templates
    deploy_container_configs
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
