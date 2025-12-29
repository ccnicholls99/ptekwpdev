#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — Project Deployment Script
#  Script: project_deploy.sh
#  Synopsis:
#    Deploy a single project by loading its configuration from projects.json,
#    scaffolding the project directory, copying global templates from
#    CONFIG_BASE, generating project-level .env and compose files, provisioning
#    dev_sources, and delegating WordPress provisioning.
#
#  Notes:
#    - Must be executed from APP_BASE/bin
#    - Uses project_config.sh to load project-level settings
#    - Reads ONLY from CONFIG_BASE (never APP_BASE)
#    - Writes ONLY to PROJECT_REPO
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

set_log --truncate "$(appcfg app_log_dir)/project_deploy.log" \
  "=== Project Deploy Run ($(date)) ==="

# ------------------------------------------------------------------------------
# Resolve config values
# ------------------------------------------------------------------------------

CONFIG_BASE="$(appcfg config_base)"
PROJECT_BASE="$(appcfg project_base)"

CONFIG_CONFIG_DIR="${CONFIG_BASE}/config"
CONFIG_DOCKER_DIR="${CONFIG_BASE}/docker"

PROJECT=""
ACTION=""
WHAT_IF=false

WORDPRESS_DEPLOY_SCRIPT="${APP_BASE}/bin/wordpress_deploy.sh"

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: project_deploy.sh -p <project_key> -a {deploy|deploy_wordpress} [-w]

Actions:
  deploy            Scaffold project, copy templates, generate .env + compose
  deploy_wordpress  Provision WordPress core into PROJECT_REPO/wordpress
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

info "Loading project configuration for '${PROJECT}'"

PROJECTS_FILE="${CONFIG_CONFIG_DIR}/projects.json"

if [[ ! -f "$PROJECTS_FILE" ]]; then
  error "Missing projects.json at ${PROJECTS_FILE}"
  exit 1
fi

project_config_load "$PROJECT"

PROJECT_REPO="$(prcfg project_repo)"
PROJECT_DOMAIN="$(prcfg project_domain)"
PROJECT_NETWORK="$(prcfg project_network)"

if [[ -z "$PROJECT_REPO" ]]; then
  error "project_repo not resolved for project '${PROJECT}'"
  exit 1
fi

info "Resolved project repo: ${PROJECT_REPO}"

# ------------------------------------------------------------------------------
# Directory scaffolding
# ------------------------------------------------------------------------------

scaffold_directories() {
  info "Scaffolding project directories"

  local dirs=(
    "${PROJECT_REPO}"
    "${PROJECT_REPO}/docker"
    "${PROJECT_REPO}/config"
    "${PROJECT_REPO}/config/proxy"
    "${PROJECT_REPO}/config/wordpress"
    "${PROJECT_REPO}/config/sqladmin"
    "${PROJECT_REPO}/config/doc"
    "${PROJECT_REPO}/src"
    "${PROJECT_REPO}/src/plugins"
    "${PROJECT_REPO}/src/themes"
    "${PROJECT_REPO}/logs"
  )

  for d in "${dirs[@]}"; do
    if $WHAT_IF; then
      whatif "Would create directory: $d"
    else
      mkdir -p "$d"
    fi
  done
}

# ------------------------------------------------------------------------------
# Copy docker templates CONFIG_BASE/docker → PROJECT_REPO/docker
# ------------------------------------------------------------------------------

copy_docker_templates() {
  info "Copying Docker engine templates"

  if [[ ! -d "$CONFIG_DOCKER_DIR" ]]; then
    error "Missing CONFIG_BASE/docker at ${CONFIG_DOCKER_DIR}"
    exit 1
  fi

  if $WHAT_IF; then
    whatif "Would copy ${CONFIG_DOCKER_DIR}/* → ${PROJECT_REPO}/docker/"
    return
  fi

  cp -R "${CONFIG_DOCKER_DIR}/"* "${PROJECT_REPO}/docker/" 2>/dev/null || true
  success "Docker templates copied"
}

# ------------------------------------------------------------------------------
# Copy container configs CONFIG_BASE/config → PROJECT_REPO/config
# ------------------------------------------------------------------------------

copy_container_configs() {
  info "Copying container config templates"

  local src="${CONFIG_CONFIG_DIR}"
  local dst="${PROJECT_REPO}/config"

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
      fi
    else
      warn "Missing container config directory: $src/$d"
    fi
  done

  success "Container config templates copied"
}

# ------------------------------------------------------------------------------
# Provision dev_sources (local + remote git)
# ------------------------------------------------------------------------------

provision_dev_sources() {
  info "Provisioning dev_sources for project '${PROJECT}'"

  local plugins_count themes_count

  plugins_count=$(jq ".projects.\"${PROJECT}\".dev_sources.plugins | length" "${PROJECTS_FILE}")
  themes_count=$(jq ".projects.\"${PROJECT}\".dev_sources.themes | length" "${PROJECTS_FILE}")

  # -------------------------
  # Plugins
  # -------------------------
  if (( plugins_count > 0 )); then
    info "Provisioning plugin dev sources"

    for i in $(seq 0 $((plugins_count - 1))); do
      local name source type init_git
      name=$(jq -r ".projects.\"${PROJECT}\".dev_sources.plugins[$i].name" "${PROJECTS_FILE}")
      source=$(jq -r ".projects.\"${PROJECT}\".dev_sources.plugins[$i].source" "${PROJECTS_FILE}")
      type=$(jq -r ".projects.\"${PROJECT}\".dev_sources.plugins[$i].type" "${PROJECTS_FILE}")
      init_git=$(jq -r ".projects.\"${PROJECT}\".dev_sources.plugins[$i].init_git // false" "${PROJECTS_FILE}")

      local dst="${PROJECT_REPO}/src/plugins/${name}"

      if [[ -d "$dst" ]]; then
        warn "Plugin '${name}' already exists — skipping"
        continue
      fi

      case "$type" in
        local)
          if $WHAT_IF; then
            whatif "Would copy local plugin '${name}' from ${source} → ${dst}"
          else
            mkdir -p "$dst"
            cp -R "${source}/"* "$dst/" 2>/dev/null || true
            info "Copied plugin '${name}' → ${dst}"
          fi
          ;;

        remote)
          if $WHAT_IF; then
            whatif "Would clone remote plugin '${name}' from ${source} → ${dst}"
          else
            git clone "$source" "$dst"
            info "Cloned plugin '${name}' → ${dst}"

            if [[ "$init_git" == "false" ]]; then
              rm -rf "${dst}/.git"
              info "Removed .git directory for plugin '${name}' (init_git=false)"
            fi
          fi
          ;;

        *)
          warn "Unknown dev_source type '${type}' for plugin '${name}' — skipping"
          ;;
      esac
    done
  fi

  # -------------------------
  # Themes
  # -------------------------
  if (( themes_count > 0 )); then
    info "Provisioning theme dev sources"

    for i in $(seq 0 $((themes_count - 1))); do
      local name source type init_git
      name=$(jq -r ".projects.\"${PROJECT}\".dev_sources.themes[$i].name" "${PROJECTS_FILE}")
      source=$(jq -r ".projects.\"${PROJECT}\".dev_sources.themes[$i].source" "${PROJECTS_FILE}")
      type=$(jq -r ".projects.\"${PROJECT}\".dev_sources.themes[$i].type" "${PROJECTS_FILE}")
      init_git=$(jq -r ".projects.\"${PROJECT}\".dev_sources.themes[$i].init_git // false" "${PROJECTS_FILE}")

      local dst="${PROJECT_REPO}/src/themes/${name}"

      if [[ -d "$dst" ]]; then
        warn "Theme '${name}' already exists — skipping"
        continue
      fi

      case "$type" in
        local)
          if $WHAT_IF; then
            whatif "Would copy local theme '${name}' from ${source} → ${dst}"
          else
            mkdir -p "$dst"
            cp -R "${source}/"* "$dst/" 2>/dev/null || true
            info "Copied theme '${name}' → ${dst}"
          fi
          ;;

        remote)
          if $WHAT_IF; then
            whatif "Would clone remote theme '${name}' from ${source} → ${dst}"
          else
            git clone "$source" "$dst"
            info "Cloned theme '${name}' → ${dst}"

            if [[ "$init_git" == "false" ]]; then
              rm -rf "${dst}/.git"
              info "Removed .git directory for theme '${name}' (init_git=false)"
            fi
          fi
          ;;

        *)
          warn "Unknown dev_source type '${type}' for theme '${name}' — skipping"
          ;;
      esac
    done
  fi

  success "dev_sources provisioned"
}

# ------------------------------------------------------------------------------
# Generate project-level .env
# ------------------------------------------------------------------------------

generate_env_file() {
  local tpl="${CONFIG_CONFIG_DIR}/env.project.tpl"
  local env_file="${PROJECT_REPO}/docker/.env"

  info "Generating project-level .env → ${env_file}"

  if [[ ! -f "$tpl" ]]; then
    error "Missing env.project.tpl at ${tpl}"
    exit 1
  fi

  if $WHAT_IF; then
    whatif "Would generate ${env_file} from ${tpl}"
    return
  fi

  : > "$env_file"

  while IFS= read -r line; do
    line=$(echo "$line" \
      | sed "s|{{project_key}}|${PROJECT}|g" \
      | sed "s|{{project_domain}}|${PROJECT_DOMAIN}|g" \
      | sed "s|{{project_network}}|${PROJECT_NETWORK}|g"
    )
    echo "$line" >> "$env_file"
  done < "$tpl"

  success ".env created"
}

# ------------------------------------------------------------------------------
# Generate compose.project.yml
# ------------------------------------------------------------------------------

generate_compose_file() {
  local tpl="${CONFIG_DOCKER_DIR}/compose.project.yml"
  local out="${PROJECT_REPO}/docker/compose.project.yml"

  info "Generating compose.project.yml → ${out}"

  if [[ ! -f "$tpl" ]]; then
    error "Missing compose.project.yml at ${tpl}"
    exit 1
  fi

  if $WHAT_IF; then
    whatif "Would generate ${out} from ${tpl}"
    return
  fi

  sed \
    -e "s|{{project_key}}|${PROJECT}|g" \
    -e "s|{{project_domain}}|${PROJECT_DOMAIN}|g" \
    -e "s|{{project_network}}|${PROJECT_NETWORK}|g" \
    "$tpl" > "$out"

  success "compose.project.yml created"
}

# ------------------------------------------------------------------------------
# Delegate WordPress provisioning
# ------------------------------------------------------------------------------

deploy_wordpress() {
  info "Delegating WordPress provisioning to wordpress_deploy.sh"

  if [[ ! -f "$WORDPRESS_DEPLOY_SCRIPT" ]]; then
    error "Missing wordpress_deploy.sh at ${WORDPRESS_DEPLOY_SCRIPT}"
    exit 1
  fi

  if $WHAT_IF; then
    whatif "Would run wordpress_deploy.sh --project ${PROJECT}"
    return
  fi

  "${WORDPRESS_DEPLOY_SCRIPT}" --project "${PROJECT}"
  success "WordPress provisioning completed"
}

# ------------------------------------------------------------------------------
# Dispatcher
# ------------------------------------------------------------------------------

case "${ACTION}" in
  deploy)
    scaffold_directories
    copy_docker_templates
    copy_container_configs
    provision_dev_sources
    generate_env_file
    generate_compose_file
    success "Project '${PROJECT}' deployed"
    ;;
  deploy_wordpress)
    deploy_wordpress
    ;;
  *)
    error "Unknown action: ${ACTION}"
    usage
    exit 1
    ;;
esac

exit 0