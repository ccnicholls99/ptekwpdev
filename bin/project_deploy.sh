#!/usr/bin/env bash
# ====Summary>>=================================================================
# PTEKWPDEV — a multi-project, bootstrap app for localized WordPress development
# github: https://github.com/ccnicholls99/ptekwpdev.git
# ------------------------------------------------------------------------------
# Script: project_deploy.sh
#
# Synopsis:
#   Deploy a project by preparing its repo, provisioning WordPress core,
#   provisioning dev sources, generating .env, copying compose files, and
#   optionally launching containers.
#
# Description:
#   - Loads project metadata via project_config v2
#   - Delegates WordPress core provisioning to wordpress_deploy.sh
#   - Copies compose.project.yml from CONFIG_BASE/docker
#   - Generates per-project .env for compose substitution
#   - Provisions dev_sources (plugins/themes)
#   - Ensures frontend + backend networks exist
#   - Optionally starts containers (--action deploy)
#
# Notes:
#   - Compose keys must be static (frontend_network, backend_network)
#   - Dynamic network names are set via name=${FRONTEND_NETWORK}
#   - WordPress core lives at PROJECT_REPO/wordpress
#
# ====<<Summary=================================================================

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

# ====Error Handling>>=====================================
_ts() { date +"%Y-%m-%d %H:%M:%S"; }
ptek_err() { COLOR_RED="\033[31m"; COLOR_RESET="\033[0m"; echo -e "${COLOR_RED}[$(_ts)] ERROR: $*${COLOR_RESET}" >&2; }

CALLER_PWD="$(pwd)"
trap 'ptek_err "Command failed (exit $?): $BASH_COMMAND"' ERR
trap 'cd "$CALLER_PWD" || true' EXIT
# ====<<Error Handling=====================================

# ====Log Handling>>=======================================
# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/output.sh"
# ====<<Log Handling=======================================

# ====App Config>>=========================================
# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/app_config.sh"
# ====<<App Config=========================================

# ====Helpers>>============================================
# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/helpers.sh"
# ====<<Helpers============================================

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: project_deploy.sh --project <key> [--action deploy] [-w|--what-if]

Options:
  --project <key>        Project key to deploy
  --action deploy        After provisioning, start containers
  -w, --what-if          Dry run (no changes applied)
  -h, --help             Show this help

Notes:
  - WordPress core provisioning is delegated to wordpress_deploy.sh
  - Compose files are copied from CONFIG_BASE/docker
  - .env is generated per project
  - Networks:
      frontend_network (per project)
      backend_network  (global, from app.json)
EOF
}

# ------------------------------------------------------------------------------
# Parse flags FIRST
# ------------------------------------------------------------------------------
PROJECT=""
ACTION=""
WHAT_IF=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --action) ACTION="$2"; shift 2 ;;
    -w|--what-if) WHAT_IF=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# ------------------------------------------------------------------------------
# Validate project key BEFORE loading project_config
# ------------------------------------------------------------------------------
if [[ -z "$PROJECT" ]]; then
  error "--project is required"
  exit 1
fi

if ! [[ "$PROJECT" =~ ^[a-z0-9_]+$ ]]; then
  error "Invalid project key: must be lowercase alphanumeric + underscores"
  exit 1
fi

# ====Project Config>>=====================================
export PTEK_PROJECT_KEY="$PROJECT"
# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/project_config.sh"
# ====<<Project Config=====================================

# ------------------------------------------------------------------------------
# Validate project exists
# ------------------------------------------------------------------------------
if [[ "$(prjcfg project_key)" != "$PROJECT" ]]; then
  error "Project '$PROJECT' not found in projects.json"
  exit 1
fi

info "Deploying project '$PROJECT'"

# ------------------------------------------------------------------------------
# Resolve metadata
# ------------------------------------------------------------------------------
PROJECT_REPO="$(prjcfg project_repo)"
DOMAIN="$(prjcfg project_domain)"

FRONTEND_NETWORK="$(prjcfg project_network)"          # per-project
BACKEND_NETWORK="$(appcfg backend_network)"           # global from app.json

WP_IMAGE="$(prjcfg wordpress.image)"
WP_CONTAINER="$(prjcfg wordpress.container_name)"
WP_VOLUME="$(prjcfg wordpress.volume_name)"
WP_PORT="$(prjcfg wordpress.port)"
WP_SSL_PORT="$(prjcfg wordpress.ssl_port)"

SQLDB_NAME="$(prjcfg secrets.sqldb_name)"
SQLDB_USER="$(prjcfg secrets.sqldb_user)"
SQLDB_PASS="$(prjcfg secrets.sqldb_pass)"

WP_ADMIN_USER="$(prjcfg secrets.wp_admin_user)"
WP_ADMIN_PASS="$(prjcfg secrets.wp_admin_pass)"
WP_ADMIN_EMAIL="$(prjcfg secrets.wp_admin_email)"

# ------------------------------------------------------------------------------
# Create project directory structure
# ------------------------------------------------------------------------------
info "Preparing project repo at: $PROJECT_REPO"

if [[ $WHAT_IF == true ]]; then
  whatif "Would create directory structure under $PROJECT_REPO"
else
  mkdir -p "$PROJECT_REPO/docker"
  mkdir -p "$PROJECT_REPO/wordpress"
  mkdir -p "$PROJECT_REPO/src/plugins"
  mkdir -p "$PROJECT_REPO/src/themes"
  mkdir -p "$PROJECT_REPO/logs"
fi

# ------------------------------------------------------------------------------
# Provision WordPress core (delegated)
# ------------------------------------------------------------------------------
info "Provisioning WordPress core via wordpress_deploy.sh"

if [[ $WHAT_IF == true ]]; then
  whatif "Would run wordpress_deploy.sh -p $PROJECT"
else
  "${PTEK_APP_BASE}/bin/wordpress_deploy.sh" -p "$PROJECT"
fi

# ------------------------------------------------------------------------------
# Provision dev_sources
# ------------------------------------------------------------------------------
info "Provisioning dev sources"

DEV_PLUGINS_JSON="$(prjcfg wordpress.dev_sources.plugins)"
DEV_THEMES_JSON="$(prjcfg wordpress.dev_sources.themes)"

# Plugins
if [[ "$DEV_PLUGINS_JSON" != "{}" ]]; then
  while IFS= read -r entry; do
    name="$(jq -r '.name' <<< "$entry")"
    source_path="$(jq -r '.source' <<< "$entry")"
    type="$(jq -r '.type' <<< "$entry")"
    init_git="$(jq -r '.init_git' <<< "$entry")"

    dest="$PROJECT_REPO/src/plugins/$name"

    info "Provisioning plugin '$name'"

    if [[ $WHAT_IF == true ]]; then
      whatif "Would provision plugin '$name' from '$source_path' to '$dest'"
    else
      if [[ "$type" == "local" ]]; then
        mkdir -p "$dest"
        cp -R "$source_path/"* "$dest/"
      else
        git clone "$source_path" "$dest"
      fi

      if [[ "$init_git" == "true" ]]; then
        (cd "$dest" && git init && git add . && git commit -m "Initial import")
      fi
    fi
  done < <(jq -c '.[]' <<< "$DEV_PLUGINS_JSON")
fi

# Themes
if [[ "$DEV_THEMES_JSON" != "{}" ]]; then
  while IFS= read -r entry; do
    name="$(jq -r '.name' <<< "$entry")"
    source_path="$(jq -r '.source' <<< "$entry")"
    type="$(jq -r '.type' <<< "$entry")"
    init_git="$(jq -r '.init_git' <<< "$entry")"

    dest="$PROJECT_REPO/src/themes/$name"

    info "Provisioning theme '$name'"

    if [[ $WHAT_IF == true ]]; then
      whatif "Would provision theme '$name' from '$source_path' to '$dest'"
    else
      if [[ "$type" == "local" ]]; then
        mkdir -p "$dest"
        cp -R "$source_path/"* "$dest/"
      else
        git clone "$source_path" "$dest"
      fi

      if [[ "$init_git" == "true" ]]; then
        (cd "$dest" && git init && git add . && git commit -m "Initial import")
      fi
    fi
  done < <(jq -c '.[]' <<< "$DEV_THEMES_JSON")
fi

# ------------------------------------------------------------------------------
# Generate .env
# ------------------------------------------------------------------------------
ENV_FILE="$PROJECT_REPO/docker/.env"

info "Generating .env at $ENV_FILE"

if [[ $WHAT_IF == true ]]; then
  whatif "Would generate .env file"
else
  cat > "$ENV_FILE" <<EOF
PROJECT_KEY=$PROJECT
PROJECT_REPO=$PROJECT_REPO

WORDPRESS_IMAGE=$WP_IMAGE
WORDPRESS_CONTAINER=$WP_CONTAINER
WORDPRESS_VOLUME=$WP_VOLUME

WORDPRESS_PORT=$WP_PORT
WORDPRESS_SSL_PORT=$WP_SSL_PORT

WORDPRESS_DOMAIN=$DOMAIN

WORDPRESS_DB_NAME=$SQLDB_NAME
WORDPRESS_DB_USER=$SQLDB_USER
WORDPRESS_DB_PASSWORD=$SQLDB_PASS

WORDPRESS_ADMIN_USER=$WP_ADMIN_USER
WORDPRESS_ADMIN_PASSWORD=$WP_ADMIN_PASS
WORDPRESS_ADMIN_EMAIL=$WP_ADMIN_EMAIL

WORDPRESS_CORE_PATH=$PROJECT_REPO/wordpress

FRONTEND_NETWORK=$FRONTEND_NETWORK
BACKEND_NETWORK=$BACKEND_NETWORK
EOF
fi

# ------------------------------------------------------------------------------
# Copy compose.project.yml
# ------------------------------------------------------------------------------
CONFIG_COMPOSE="$(appcfg config_base)/docker/compose.project.yml"
DEST_COMPOSE="$PROJECT_REPO/docker/compose.project.yml"

info "Copying compose.project.yml"

if [[ $WHAT_IF == true ]]; then
  whatif "Would copy $CONFIG_COMPOSE to $DEST_COMPOSE"
else
  cp "$CONFIG_COMPOSE" "$DEST_COMPOSE"
fi

# ------------------------------------------------------------------------------
# Ensure Docker networks exist
# ------------------------------------------------------------------------------
info "Ensuring Docker networks exist"

if [[ $WHAT_IF == true ]]; then
  whatif "Would create network '$FRONTEND_NETWORK' if missing"
  whatif "Would create network '$BACKEND_NETWORK' if missing"
else
  docker network inspect "$FRONTEND_NETWORK" >/dev/null 2>&1 || docker network create "$FRONTEND_NETWORK"
  docker network inspect "$BACKEND_NETWORK"  >/dev/null 2>&1 || docker network create "$BACKEND_NETWORK"
fi

# ------------------------------------------------------------------------------
# Optionally start containers
# ------------------------------------------------------------------------------
if [[ "$ACTION" == "deploy" ]]; then
  info "Starting containers"

  if [[ $WHAT_IF == true ]]; then
    whatif "Would run docker compose up -d"
  else
    (cd "$PROJECT_REPO/docker" && docker compose -f compose.project.yml up -d)
  fi
fi

success "Project deployment complete for '$PROJECT'"
exit 0
