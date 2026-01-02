#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — Project Deploy Script
#  Script: project_deploy.sh
#
#  Description:
#    Scaffolds a project filesystem and optionally provisions WordPress and/or
#    launches the project. This script relies on:
#      - app_config.sh  (appcfg)
#      - project_config.sh (prjcfg)
#
#    Responsibilities:
#      - Validate project exists
#      - Create project directory structure
#      - Generate project-level .env
#      - Copy compose.project.yml from CONFIG_BASE/docker
#      - Optionally run wordpress_deploy.sh
#      - Optionally run project_launch.sh
#
#    Non-responsibilities:
#      - Docker lifecycle (handled by project_launch.sh)
#      - Metadata creation (handled by project_create.sh)
#      - Modifying app.json, app.config, or projects.json
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail

# ------------------------------------------------------------------------------
# Resolve APP_BASE
# ------------------------------------------------------------------------------

PTEK_APP_BASE="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"
export PTEK_APP_BASE

# ------------------------------------------------------------------------------
# Load app config + logging
# ------------------------------------------------------------------------------

# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/app_config.sh"

set_log --truncate "$(appcfg app_log_dir)/project_deploy.log" \
  "=== Project Deploy Run ($(date)) ==="

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: project_deploy.sh [options]

Options:
  -p, --project <key>       Project key (required)
  -f, --force               Allow reuse of existing project directory
  -w, --what-if             Dry run (no changes applied)
  --auto-wordpress          Automatically run wordpress_deploy.sh
  --auto-launch             Automatically run project_launch.sh start
  -h, --help                Show this help

Description:
  Scaffolds a project's filesystem and generates configuration files based on
  app.json/app.config and projects.json. Copies compose.project.yml from
  CONFIG_BASE/docker. Optionally provisions WordPress and/or launches the project.

Notes:
  - This script does NOT start or stop Docker containers unless --with-launch.
  - This script does NOT create project metadata; use project_create.sh first.
EOF
}

# ------------------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------------------

PROJECT_KEY=""
FORCE=0
WHAT_IF=0
AUTO_WORDPRESS=0
AUTO_LAUNCH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project)
      PROJECT_KEY="$2"; shift 2;;
    -f|--force)
      FORCE=1; shift;;
    -w|--what-if)
      WHAT_IF=1; shift;;
    --auto-wordpress)
      AUTO_WORDPRESS=1; shift;;
    --auto-launch)
      AUTO_LAUNCH=1; shift;;
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
# Load project config
# ------------------------------------------------------------------------------

# New: tell project_config.sh which project to load
export PTEK_PROJECT_KEY="$PROJECT_KEY"

# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/project_config.sh"

if [[ "$(prjcfg project_key)" != "$PROJECT_KEY" ]]; then
  error "Loaded project_key '$(prjcfg project_key)' does not match requested '$PROJECT_KEY'"
  exit 1
fi

# ------------------------------------------------------------------------------
# Resolve paths
# ------------------------------------------------------------------------------

CONFIG_BASE="$(appcfg config_base)"

# New: use canonical, normalized repo from project_config
PROJECT_REPO="$(prjcfg project_repo)"

DOCKER_DIR="${PROJECT_REPO}/docker"
WORDPRESS_DIR="${PROJECT_REPO}/wordpress"
SRC_DIR="${PROJECT_REPO}/src"
PLUGINS_DIR="${SRC_DIR}/plugins"
THEMES_DIR="${SRC_DIR}/themes"
DB_DIR="${PROJECT_REPO}/db"

ENV_FILE="${DOCKER_DIR}/.env"
COMPOSE_SRC="${CONFIG_BASE}/docker/compose.project.yml"
COMPOSE_DEST="${DOCKER_DIR}/compose.project.yml"

info "Resolved paths:"
info "  PROJECT_REPO   = ${PROJECT_REPO}"
info "  DOCKER_DIR     = ${DOCKER_DIR}"
info "  WORDPRESS_DIR  = ${WORDPRESS_DIR}"
info "  SRC_DIR        = ${SRC_DIR}"
info "  PLUGINS_DIR    = ${PLUGINS_DIR}"
info "  THEMES_DIR     = ${THEMES_DIR}"
info "  DB_DIR         = ${DB_DIR}"

# ------------------------------------------------------------------------------
# WHAT-IF wrappers
# ------------------------------------------------------------------------------

run() {
  if [[ "$WHAT_IF" -eq 1 ]]; then
    info "[WHAT-IF] $*"
  else
    "$@"
  fi
}

run_mkdir() {
  if [[ "$WHAT_IF" -eq 1 ]]; then
    info "[WHAT-IF] mkdir -p $*"
  else
    mkdir -p "$@"
  fi
}

run_copy() {
  local src="$1"
  local dest="$2"
  if [[ "$WHAT_IF" -eq 1 ]]; then
    info "[WHAT-IF] cp $src $dest"
  else
    cp "$src" "$dest"
  fi
}

run_write_file() {
  local path="$1"
  shift
  if [[ "$WHAT_IF" -eq 1 ]]; then
    info "[WHAT-IF] write file: $path"
    return 0
  fi
  cat > "$path" <<EOF
$*
EOF
}

# ------------------------------------------------------------------------------
# Safety checks
# ------------------------------------------------------------------------------

if [[ -d "$PROJECT_REPO" && "$FORCE" -ne 1 ]]; then
  error "Project directory already exists: $PROJECT_REPO"
  error "Use --force to allow deploying into an existing directory."
  exit 1
fi

if [[ ! -f "$COMPOSE_SRC" ]]; then
  error "Missing compose.project.yml template:"
  error "  $COMPOSE_SRC"
  exit 1
fi

# ------------------------------------------------------------------------------
# Create directory structure
# ------------------------------------------------------------------------------

create_directories() {
  info "Creating directory structure"

  run_mkdir "$PROJECT_REPO"
  run_mkdir "$DOCKER_DIR"
  run_mkdir "$WORDPRESS_DIR"
  run_mkdir "$SRC_DIR"
  run_mkdir "$PLUGINS_DIR"
  run_mkdir "$THEMES_DIR"
  run_mkdir "$DB_DIR"

  success "Directory structure prepared"
}

# ------------------------------------------------------------------------------
# Generate .env file
# ------------------------------------------------------------------------------

generate_env_file() {
  info "Generating project .env file at: $ENV_FILE"

  run_write_file "$ENV_FILE" "\
# Generated by project_deploy.sh for project: $(prjcfg project_key)

PROJECT_KEY=$(prjcfg project_key)
PROJECT_DOMAIN=$(prjcfg domain)

BACKEND_NETWORK=$(appcfg backend_network)
PROJECT_NETWORK=$(prjcfg network)

SQLDB_IMAGE=$(appcfg database.sqldb_image)
SQLDB_VERSION=$(appcfg database.sqldb_version)
SQLDB_PORT=$(appcfg database.sqldb_port)

SQLDB_NAME=$(prjcfg secrets.sqldb_name)
SQLDB_USER=$(prjcfg secrets.sqldb_user)
SQLDB_PASS=$(prjcfg secrets.sqldb_pass)

WORDPRESS_IMAGE=$(appcfg wordpress_defaults.image)
WORDPRESS_HTTP_PORT=$(prjcfg http_port)
WORDPRESS_HTTPS_PORT=$(prjcfg https_port)

WP_ADMIN_USER=$(prjcfg secrets.wp_admin_user)
WP_ADMIN_PASS=$(prjcfg secrets.wp_admin_pass)
WP_ADMIN_EMAIL=$(prjcfg secrets.wp_admin_email)

ASSETS_CONTAINER=$(appcfg assets.container)
ASSETS_ROOT=$(appcfg assets.root)
"

  success ".env file generated"
}

# ------------------------------------------------------------------------------
# Copy compose.project.yml
# ------------------------------------------------------------------------------

copy_compose_file() {
  info "Copying compose.project.yml from CONFIG_BASE/docker"

  run_copy "$COMPOSE_SRC" "$COMPOSE_DEST"

  success "compose.project.yml copied"
}

# ------------------------------------------------------------------------------
# Provision WordPress (optional)
# ------------------------------------------------------------------------------

provision_wordpress() {
  if [[ "$AUTO_WORDPRESS" -eq 0 ]]; then
    info "Skipping WordPress provisioning (no --auto-wordpress)"
    return 0
  fi

  info "Provisioning WordPress via wordpress_deploy.sh"

  local cmd=("${PTEK_APP_BASE}/bin/wordpress_deploy.sh" "--project" "$PROJECT_KEY")

  if [[ "$WHAT_IF" -eq 1 ]]; then
    info "[WHAT-IF] ${cmd[*]}"
    return 0
  fi

  "${cmd[@]}"

  success "WordPress provisioning completed"
}

# ------------------------------------------------------------------------------
# Auto-launch project (optional)
# ------------------------------------------------------------------------------

auto_launch() {
  if [[ "$AUTO_LAUNCH" -eq 0 ]]; then
    info "Skipping project launch (no --auto-launch)"
    return 0
  fi

  info "Launching project via project_launch.sh"

  local cmd=("${PTEK_APP_BASE}/bin/project_launch.sh" "--project" "$PROJECT_KEY" "start")

  if [[ "$WHAT_IF" -eq 1 ]]; then
    info "[WHAT-IF] ${cmd[*]}"
    return 0
  fi

  "${cmd[@]}"

  success "Project launched"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

create_directories
generate_env_file
copy_compose_file
provision_wordpress
auto_launch

success "Project deployment completed for: $(prjcfg project_key)"