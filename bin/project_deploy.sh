#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — Project Deploy Script
#  Script: project_deploy.sh
#
#  Description:
#    Scaffolds a project filesystem and optional WordPress provisioning based on
#    app-level config (app_config.sh) and project-level config (project_config.sh).
#
#    Responsibilities:
#      - Validate project exists in projects.json
#      - Resolve app + project paths
#      - Create project directory structure under PROJECT_BASE
#      - Generate project-level .env and compose.project.yml
#      - Optionally invoke wordpress_deploy.sh for WordPress core provisioning
#
#    Non-responsibilities:
#      - Docker container lifecycle (handled by project_launch.sh)
#      - Project metadata creation (handled by project_create.sh)
#      - Modifying app.json, app.config, or projects.json structure
#
#  Notes:
#    - Uses Option C logging via app_config.sh/output.sh
#    - Never exports environment variables
#    - Never deletes anything; --force only allows reusing existing dirs
# ==============================================================================


set -o errexit
set -o nounset
set -o pipefail

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: project_deploy.sh [options]

Options:
  -p, --project <key>     Project key (required)
  -f, --force             Allow reuse of existing project directory
  -c, --core              Deploy Wordpress Core
  -w, --what-if           Dry run (no changes applied)
  -h, --help              Show this help

Description:
  Scaffolds a project's filesystem and generates configuration files based on
  app.json/app.config and projects.json. Optionally runs WordPress provisioning
  via wordpress_deploy.sh.

Notes:
  - This script does NOT start or stop Docker containers; use project_launch.sh.
  - This script does NOT create project metadata; use project_create.sh first.
EOF
}

# ------------------------------------------------------------------------------
# Ensure project config is laoded
# ------------------------------------------------------------------------------
project_config_loader() {
  
  info "Loading project configuration for '${PROJECT_KEY}'"

  # Expect project_config.sh to populate PTEKPRCFG for $PROJECT_KEY
  # Common pattern: consume PROJECT_KEY via env or argument; adapt as needed.
  export PTEK_PROJECT_KEY="$PROJECT_KEY"

  project_config_load "$PROJECT_KEY"

  # Defensive check
  if [[ -z "${PTEKPRCFG[project_key]:-}" ]]; then
    error "project_config.sh did not populate PTEKPRCFG[project_key]"
    error "Ensure project_config.sh supports PTEK_PROJECT_KEY=$PROJECT_KEY"
    exit 1
  fi
}


# ------------------------------------------------------------------------------
# Preserve caller directory
# ------------------------------------------------------------------------------

PTEK_CALLER_PWD="$(pwd)"
ptekwp_cleanup() {
  cd "$PTEK_CALLER_PWD" || true
}
trap ptekwp_cleanup EXIT


# ------------------------------------------------------------------------------
# Resolve APP_BASE
# ------------------------------------------------------------------------------

PTEK_APP_BASE="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"
export PTEK_APP_BASE

# ------------------------------------------------------------------------------
# Load support libraries app_config, output, helpers, and project_config
# ------------------------------------------------------------------------------
CHECK_FILE="${PTEK_APP_BASE}/lib/app_config.sh"
# shellcheck source=/dev/null
if [[ -f $CHECK_FILE ]]; then
  source "$CHECK_FILE"
else
  printf "ERROR: Unable to source %s" "$CHECK_FILE"
  exit 1 
fi

CHECK_FILE="${PTEK_APP_BASE}/lib/output.sh"
# shellcheck source=/dev/null
if [[ -f $CHECK_FILE ]]; then
  source "$CHECK_FILE"
else
  printf "ERROR: Unable to source %s" "$CHECK_FILE"
  exit 1 
fi
CHECK_FILE=

set_log --truncate "$(appcfg app_log_dir)/project_deploy.log" \
  "=== Project Deploy Run ($(date)) ==="

CHECK_FILE="${PTEK_APP_BASE}/lib/helpers.sh"
# shellcheck source=/dev/null
if [[ -f $CHECK_FILE ]]; then
  source "$CHECK_FILE"
else
  printf "ERROR: Unable to source %s" "$CHECK_FILE"
  exit 1 
fi
CHECK_FILE=

CHECK_FILE="${PTEK_APP_BASE}/lib/project_config.sh"
# shellcheck source=/dev/null
if [[ -f $CHECK_FILE ]]; then
  source "$CHECK_FILE"
else
  printf "ERROR: Unable to source %s" "$CHECK_FILE"
  exit 1 
fi
CHECK_FILE=

# ------------------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------------------
CONFIG_BASE=
PROJECT_BASE=
PROJECT_KEY=""
WORDPRESS_CORE=1
FORCE=0
WHAT_IF=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project)
      PROJECT_KEY="$2"; shift 2;;
    -f|--force)
      FORCE=1; shift;;
    -c|--core)
      WORDPRESS_CORE=0; shift;;
    -w|--what-if)
      WHAT_IF=0; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      error "Unknown option: $1"
      usage
      exit 1;;
  esac
done

if [[ -z "$PROJECT_KEY" ]]; then
  error "Missing required option: --project <key>"
  usage
  exit 1
fi

info "Deploying project: $PROJECT_KEY"


# ------------------------------------------------------------------------------
# Resolve config values
# ------------------------------------------------------------------------------

CONFIG_BASE="$(appcfg config_base)"
# The project repo where this project will deployed under PROJECT_KEY. i.e. $PROJECT_BASE/$PROJECT_KEY
PROJECT_BASE="$(appcfg project_base)"

CONFIG_CONFIG_DIR="${CONFIG_BASE}/config"
CONFIG_DOCKER_DIR="${CONFIG_BASE}/docker"

WORDPRESS_DEPLOY_CMD="${PTEK_APP_BASE}/bin/wordpress_deploy.sh"

# ------------------------------------------------------------------------------
# Load project configuration
# ------------------------------------------------------------------------------
PROJECTS_FILE="${CONFIG_CONFIG_DIR}/projects.json"

if [[ ! -f "$PROJECTS_FILE" ]]; then
  error "Missing projects.json at ${PROJECTS_FILE}"
  exit 1
fi

project_config_loader

PROJECT_REPO="$(prcfg project_repo)"
PROJECT_DOMAIN="$(prcfg project_domain)"
PROJECT_NETWORK="$(prcfg project_network)"

if [[ -z "$PROJECT_REPO" ]]; then
  error "project_repo not resolved for project '${PROJECT_KEY}'"
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
    if [[ $WHAT_IF -eq 0 ]]; then
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

  if [[ $WHAT_IF -eq 0 ]]; then
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
      if [[ $WHAT_IF -eq 0 ]]; then
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
  info "Provisioning dev_sources for project '${PROJECT_KEY}'"

  local plugins_count themes_count

  plugins_count=$(jq ".projects.\"${PROJECT_KEY}\".dev_sources.plugins | length" "${PROJECTS_FILE}")
  themes_count=$(jq ".projects.\"${PROJECT_KEY}\".dev_sources.themes | length" "${PROJECTS_FILE}")

  # -------------------------
  # Plugins
  # -------------------------
  if (( plugins_count > 0 )); then
    info "Provisioning plugin dev sources"

    for i in $(seq 0 $((plugins_count - 1))); do
      local name source type init_git
      name=$(jq -r ".projects.\"${PROJECT_KEY}\".dev_sources.plugins[$i].name" "${PROJECTS_FILE}")
      source=$(jq -r ".projects.\"${PROJECT_KEY}\".dev_sources.plugins[$i].source" "${PROJECTS_FILE}")
      type=$(jq -r ".projects.\"${PROJECT_KEY}\".dev_sources.plugins[$i].type" "${PROJECTS_FILE}")
      init_git=$(jq -r ".projects.\"${PROJECT_KEY}\".dev_sources.plugins[$i].init_git // false" "${PROJECTS_FILE}")

      local dst="${PROJECT_REPO}/src/plugins/${name}"

      if [[ -d "$dst" ]]; then
        warn "Plugin '${name}' already exists — skipping"
        continue
      fi

      case "$type" in
        local)
          if [[ $WHAT_IF -eq 0 ]]; then
            whatif "Would copy local plugin '${name}' from ${source} → ${dst}"
          else
            mkdir -p "$dst"
            cp -R "${source}/"* "$dst/" 2>/dev/null || true
            info "Copied plugin '${name}' → ${dst}"
          fi
          ;;

        remote)
          if [[ $WHAT_IF -eq 0 ]]; then
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
      name=$(jq -r ".projects.\"${PROJECT_KEY}\".dev_sources.themes[$i].name" "${PROJECTS_FILE}")
      source=$(jq -r ".projects.\"${PROJECT_KEY}\".dev_sources.themes[$i].source" "${PROJECTS_FILE}")
      type=$(jq -r ".projects.\"${PROJECT_KEY}\".dev_sources.themes[$i].type" "${PROJECTS_FILE}")
      init_git=$(jq -r ".projects.\"${PROJECT_KEY}\".dev_sources.themes[$i].init_git // false" "${PROJECTS_FILE}")

      local dst="${PROJECT_REPO}/src/themes/${name}"

      if [[ -d "$dst" ]]; then
        warn "Theme '${name}' already exists — skipping"
        continue
      fi

      case "$type" in
        local)
          if [[ $WHAT_IF -eq 0 ]]; then
            whatif "Would copy local theme '${name}' from ${source} → ${dst}"
          else
            mkdir -p "$dst"
            cp -R "${source}/"* "$dst/" 2>/dev/null || true
            info "Copied theme '${name}' → ${dst}"
          fi
          ;;

        remote)
          if [[ $WHAT_IF -eq 0 ]]; then
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

  if [[ $WHAT_IF -eq 0 ]]; then
    whatif "Would generate ${env_file} from ${tpl}"
    return
  fi

  : > "$env_file"

  while IFS= read -r line; do
    line=$(echo "$line" \
      | sed "s|{{project_key}}|${PROJECT_KEY}|g" \
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

  if [[ $WHAT_IF -eq 0 ]]; then
    whatif "Would generate ${out} from ${tpl}"
    return
  fi

  sed \
    -e "s|{{project_key}}|${PROJECT_KEY}|g" \
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

  if [[ ! -f "$WORDPRESS_DEPLOY_CMD" ]]; then
    error "Missing wordpress_deploy.sh at ${WORDPRESS_DEPLOY_CMD}"
    exit 1
  fi

  if [[ $WHAT_IF -eq 0 ]]; then
    whatif "Would run wordpress_deploy.sh --project ${PROJECT_KEY}"
    return
  fi

  "${WORDPRESS_DEPLOY_CMD}" --project "${PROJECT_KEY}"
  success "WordPress provisioning completed"
}

# ------------------------------------------------------------------------------
# Dispatcher
# ------------------------------------------------------------------------------
dispatch() {
  scaffold_directories
  copy_container_configs
  provision_dev_sources
  generate_env_file
  #generate_compose_file
  copy_docker_templates
  if [[ $WORDPRESS_CORE -eq 0 ]]; then
    deploy_wordpress
  fi
  success "Project '${PROJECT_KEY}' deployed"
}

dispatch
exit 0