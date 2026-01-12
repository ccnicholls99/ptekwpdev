#!/usr/bin/env bash
# ====Summary>>=================================================================
# PTEKWPDEV — WordPress core provisioning for a single project
#
# Script: wordpress_deploy.sh
#
# Synopsis:
#   Provision WordPress core, config, and initial install for a project,
#   using containerized wp-cli and metadata from project_config v2.
#
# Description:
#   - Loads project metadata via project_config v2 (prjcfg)
#   - Resolves project repo via prjcfg project_repo
#   - Provisions WordPress into \$PROJECT_REPO/wordpress
#   - Uses containerized wp-cli (temporary container only)
#   - Idempotent at each step (core, config, install, admin user)
#   - Writes a provisioning manifest into the project repo
#
# Usage:
#   wordpress_deploy.sh -p <key> [--what-if|-w] [--verbose|-v]
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
Usage: $(basename "$0") -p <key> [options]

Options:
  -p | --project <key>   Project key (required)
  -v | --verbose         Verbose logging
  -w | --what-if         Log actions but do not execute
  -h | --help            Show this help

Notes:
  - WordPress core is provisioned into the project repo under 'wordpress'
  - Project metadata is loaded via project_config v2 (prjcfg)
  - Uses containerized wp-cli (temporary container only)
EOF
}

# ------------------------------------------------------------------------------
# Globals
# ------------------------------------------------------------------------------
PROJECT=""
WHAT_IF=false
VERBOSE=false

PROJECT_REPO=""
WORDPRESS_DIR=""
MANIFEST_FILE=""
WORDPRESS_URL=""

WP_CLI_IMAGE_DEFAULT="wordpress:cli"
WP_CLI_IMAGE="$WP_CLI_IMAGE_DEFAULT"

MANIFEST_CORE=false
MANIFEST_CONFIG=false
MANIFEST_INSTALLED=false
MANIFEST_ADMIN=false

# ------------------------------------------------------------------------------
# Parse flags FIRST
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project) PROJECT="$2"; shift 2 ;;
    -v|--verbose) VERBOSE=true; shift ;;
    -w|--what-if) WHAT_IF=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# ------------------------------------------------------------------------------
# Validate project key BEFORE loading project_config
# ------------------------------------------------------------------------------
if [[ -z "$PROJECT" ]]; then
  echo "ERROR: --project is required" >&2
  usage
  exit 1
fi

if ! [[ "$PROJECT" =~ ^[a-z0-9_]+$ ]]; then
  echo "ERROR: Invalid project key: must be lowercase alphanumeric + underscores" >&2
  exit 1
fi

# ====Project Config>>=====================================
export PTEK_PROJECT_KEY="$PROJECT"
# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/project_config.sh"
# ====<<Project Config=====================================

# ------------------------------------------------------------------------------
# Validate project exists in projects.json
# ------------------------------------------------------------------------------
if [[ "$(prjcfg project_key)" != "$PROJECT" ]]; then
  error "Project '$PROJECT' not found in projects.json"
  exit 1
fi

# ------------------------------------------------------------------------------
# Bootstrap logging & core paths
# ------------------------------------------------------------------------------
PROJECT_REPO="$(prjcfg project_repo)"
if [[ -z "$PROJECT_REPO" ]]; then
  error "project_repo is empty for project '$PROJECT'"
  exit 2
fi

mkdir -p "${PROJECT_REPO}/logs"
export LOGFILE="${PROJECT_REPO}/logs/wordpress_deploy.log"

if [[ "$VERBOSE" == true ]]; then
  export PTEK_VERBOSE=1
fi

WORDPRESS_DIR="${PROJECT_REPO}/wordpress"
MANIFEST_FILE="${WORDPRESS_DIR}/.provisioned.json"

# ------------------------------------------------------------------------------
# Load project context from v2 schema
# ------------------------------------------------------------------------------
info "Loading project context for '$PROJECT'"

PROJECT_TITLE="$(prjcfg project_title)"
PROJECT_TITLE="${PROJECT_TITLE:-$PROJECT}"

DOMAIN="$(prjcfg project_domain)"
NETWORK="$(prjcfg project_network)"

SQLDB_NAME="$(prjcfg secrets.sqldb_name)"
SQLDB_USER="$(prjcfg secrets.sqldb_user)"
SQLDB_PASS="$(prjcfg secrets.sqldb_pass)"

WORDPRESS_HOST="$(prjcfg wordpress.host)"
WORDPRESS_PORT="$(prjcfg wordpress.port)"
WORDPRESS_SSL_PORT="$(prjcfg wordpress.ssl_port)"
WORDPRESS_IMAGE="$(prjcfg wordpress.image)"

WP_ADMIN_USER="$(prjcfg secrets.wp_admin_user)"
WP_ADMIN_PASS="$(prjcfg secrets.wp_admin_pass)"
WP_ADMIN_EMAIL="$(prjcfg secrets.wp_admin_email)"

WP_CLI_IMAGE="${WP_CLI_IMAGE_DEFAULT}"

# ------------------------------------------------------------------------------
# Validate project context
# ------------------------------------------------------------------------------
info "Validating project context"

if [[ -z "$SQLDB_NAME" || -z "$SQLDB_USER" || -z "$SQLDB_PASS" ]]; then
  error "Database secrets incomplete (sqldb_name/user/pass)"
  exit 2
fi

if [[ -z "$WORDPRESS_HOST" ]]; then
  error "wordpress.host missing"
  exit 2
fi

if [[ -z "$WORDPRESS_PORT" && -z "$WORDPRESS_SSL_PORT" ]]; then
  error "wordpress.port or wordpress.ssl_port required"
  exit 2
fi

if [[ -z "$WP_ADMIN_USER" || -z "$WP_ADMIN_EMAIL" || -z "$WP_ADMIN_PASS" ]]; then
  error "Admin credentials incomplete (wp_admin_user/wp_admin_email/wp_admin_pass)"
  exit 2
fi

# ------------------------------------------------------------------------------
# Compute WordPress URL
# ------------------------------------------------------------------------------
compute_wordpress_url() {
  if [[ -n "$WORDPRESS_SSL_PORT" ]]; then
    WORDPRESS_URL="https://${WORDPRESS_HOST}:${WORDPRESS_SSL_PORT}"
  else
    WORDPRESS_URL="http://${WORDPRESS_HOST}:${WORDPRESS_PORT}"
  fi
}

compute_wordpress_url

# ------------------------------------------------------------------------------
# wp-cli runner (containerized)
# ------------------------------------------------------------------------------
run_wp() {
  local wp_args=("$@")

  if [[ "$WHAT_IF" == true ]]; then
    whatif "wp ${wp_args[*]}"
    return 0
  fi

  # We assume the DB host is reachable via the project network;
  # use NETWORK from project config as docker network.
  local docker_network="$NETWORK"
  if [[ -z "$docker_network" ]]; then
    error "No Docker network configured (project_network is empty)"
    exit 2
  fi

  info "Running wp-cli via '$WP_CLI_IMAGE' on network '$docker_network'"

  docker run --rm \
    -v "${WORDPRESS_DIR}:/var/www/html" \
    --network "${docker_network}" \
    -e WORDPRESS_DB_HOST="db" \
    -e WORDPRESS_DB_USER="${SQLDB_USER}" \
    -e WORDPRESS_DB_PASSWORD="${SQLDB_PASS}" \
    -e WORDPRESS_DB_NAME="${SQLDB_NAME}" \
    "${WP_CLI_IMAGE}" \
    wp "${wp_args[@]}"
}

# ------------------------------------------------------------------------------
# Provisioning steps
# ------------------------------------------------------------------------------
ensure_wordpress_directory() {
  if [[ -d "$WORDPRESS_DIR" ]]; then
    info "WordPress directory exists: $WORDPRESS_DIR"
  else
    if [[ "$WHAT_IF" == true ]]; then
      whatif "mkdir -p '$WORDPRESS_DIR'"
      return
    fi
    mkdir -p "$WORDPRESS_DIR"
    info "Created $WORDPRESS_DIR"
  fi
}

provision_core() {
  local marker="${WORDPRESS_DIR}/wp-includes/version.php"

  if [[ -f "$marker" ]]; then
    info "WordPress core already present"
    MANIFEST_CORE=true
    return
  fi

  info "Downloading WordPress core..."

  run_wp core download --force

  if [[ -f "$marker" || "$WHAT_IF" == true ]]; then
    MANIFEST_CORE=true
  else
    error "Core download failed"
    exit 3
  fi
}

provision_config() {
  local cfg="${WORDPRESS_DIR}/wp-config.php"

  if [[ -f "$cfg" ]]; then
    info "wp-config.php exists"
    MANIFEST_CONFIG=true
    return
  fi

  info "Generating wp-config.php..."

  run_wp config create \
    --dbname="$SQLDB_NAME" \
    --dbuser="$SQLDB_USER" \
    --dbpass="$SQLDB_PASS" \
    --dbhost="db" \
    --dbprefix="wp_" \
    --skip-check \
    --force

  run_wp config shuffle-salts

  if [[ -f "$cfg" || "$WHAT_IF" == true ]]; then
    MANIFEST_CONFIG=true
  else
    error "Config generation failed"
    exit 3
  fi
}

install_wordpress() {
  if run_wp core is-installed >/dev/null 2>&1; then
    info "WordPress already installed"
    MANIFEST_INSTALLED=true
    return
  fi

  info "Installing WordPress..."

  run_wp core install \
    --url="$WORDPRESS_URL" \
    --title="$PROJECT_TITLE" \
    --admin_user="$WP_ADMIN_USER" \
    --admin_password="$WP_ADMIN_PASS" \
    --admin_email="$WP_ADMIN_EMAIL"

  if [[ "$WHAT_IF" == true ]]; then
    MANIFEST_INSTALLED=true
  elif run_wp core is-installed >/dev/null 2>&1; then
    MANIFEST_INSTALLED=true
  else
    error "Installation failed"
    exit 3
  fi
}

ensure_admin_user() {
  if run_wp user get "$WP_ADMIN_USER" >/dev/null 2>&1; then
    info "Admin user exists"
    MANIFEST_ADMIN=true
    return
  fi

  info "Creating admin user..."

  run_wp user create \
    "$WP_ADMIN_USER" \
    "$WP_ADMIN_EMAIL" \
    --user_pass="$WP_ADMIN_PASS" \
    --role=administrator

  if [[ "$WHAT_IF" == true ]]; then
    MANIFEST_ADMIN=true
  elif run_wp user get "$WP_ADMIN_USER" >/dev/null 2>&1; then
    MANIFEST_ADMIN=true
  else
    error "Admin user creation failed"
    exit 3
  fi
}

# ------------------------------------------------------------------------------
# Manifest
# ------------------------------------------------------------------------------
write_manifest() {
  if [[ "$WHAT_IF" == true ]]; then
    whatif "Write manifest to '$MANIFEST_FILE'"
    return
  fi

  cat > "$MANIFEST_FILE" <<EOF
{
  "project": "${PROJECT}",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "core": ${MANIFEST_CORE},
  "config": ${MANIFEST_CONFIG},
  "installed": ${MANIFEST_INSTALLED},
  "admin_user": ${MANIFEST_ADMIN},
  "wordpress_url": "${WORDPRESS_URL}",
  "wordpress_dir": "${WORDPRESS_DIR}"
}
EOF

  info "Wrote manifest: $MANIFEST_FILE"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
info "WordPress deployment for '$PROJECT'"
info "WHAT_IF=${WHAT_IF} VERBOSE=${VERBOSE}"
info "APP_BASE=${PTEK_APP_BASE}"
info "Project repo: ${PROJECT_REPO}"
info "WordPress directory: ${WORDPRESS_DIR}"
info "WordPress URL: ${WORDPRESS_URL}"
info "wp-cli image: ${WP_CLI_IMAGE}"

ensure_wordpress_directory
provision_core
provision_config
install_wordpress
ensure_admin_user
write_manifest

success "WordPress deployment completed for '${PROJECT}'."
exit 0
