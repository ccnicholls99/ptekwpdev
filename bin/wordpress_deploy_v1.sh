#!/usr/bin/env bash
#
# Script: wordpress_deploy.sh
# Purpose: Provision WordPress core, config, and initial install for a single project.
#          - Uses containerized wp-cli (temporary container only)
#          - Reads all config from project_config.sh via PTEKPRCFG + prcfg()
#          - Resolves project root via project_resolve_repo()
#          - Idempotent at each step (core, config, install, admin user)
#          - Writes a provisioning manifest for auditability
#
# Usage:
#   wordpress_deploy.sh -p | --project <PROJECT> [--what-if|-w] [--verbose|-v]
#
set -euo pipefail

# -----------------------------------------------------------------------------
# Resolve APP_BASE (canonical pattern)
# -----------------------------------------------------------------------------
PTEK_APP_BASE="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"
export PTEK_APP_BASE

# -----------------------------------------------------------------------------
# Load core libs
# -----------------------------------------------------------------------------

# app_config.sh
CHECK_FILE="${PTEK_APP_BASE}/lib/app_config.sh"
if [[ -f $CHECK_FILE ]]; then
  source "$CHECK_FILE"
else
  printf "ERROR: App Config could not located at %s\n" "$CHECK_FILE"
  exit 1
fi
CHECK_FILE=


# Safe accessor
#prcfg_or_empty() {
#  prcfg "$1" 2>/dev/null || echo ""
#}

# -----------------------------------------------------------------------------
# Globals
# -----------------------------------------------------------------------------

WHAT_IF=false
VERBOSE=false
PROJECT_KEY=""

PROJECT_REPO=""
WORDPRESS_DIR=""
MANIFEST_FILE=""

WP_CLI_IMAGE_DEFAULT="wordpress:cli"
WP_CLI_IMAGE=""

WORDPRESS_URL=""

MANIFEST_CORE=false
MANIFEST_CONFIG=false
MANIFEST_INSTALLED=false
MANIFEST_ADMIN=false

# -----------------------------------------------------------------------------
# Usage
# -----------------------------------------------------------------------------

print_usage() {
  cat <<EOF
Usage: $(basename "$0") <PROJECT> [options]

<PROJECT>             Valid Project Key from CONFIG_BASE/config/projects.json

Options:
  -h | --help         Show usage
  -v | --verbose      Verbose logging
  -w | --what-if      Log actions but do not execute

Provision WordPress for a single project:
  - Downloads core (if missing)
  - Generates wp-config.php (if missing)
  - Installs WordPress (if not installed)
  - Creates admin user (if missing)
  - Writes provisioning manifest
EOF
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

parse_args() {
  if [[ $# -lt 1 ]]; then
    print_usage
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --what-if|-w)
        WHAT_IF=true
        shift
        ;;
      --verbose|-v)
        VERBOSE=true
        shift
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      -*)
        echo "ERROR: Unknown option: $1" >&2
        print_usage
        exit 1
        ;;
      *)
        if [[ -z "${PROJECT_KEY}" ]]; then
          PROJECT_KEY="$1"
          shift
        else
          echo "ERROR: Unexpected argument: $1" >&2
          print_usage
          exit 1
        fi
        ;;
    esac
  done
}

# -----------------------------------------------------------------------------
# Config + logging bootstrap
# -----------------------------------------------------------------------------

bootstrap_config_and_logging() {
  local CHECK_FILE

  # Load output.sh
  CHECK_FILE="${PTEK_APP_BASE}/lib/output.sh"
  if [[ -f $CHECK_FILE ]]; then
    source "$CHECK_FILE"
  else
    printf "ERROR: Logging utility could not be located at %s\n" "$CHECK_FILE"
    exit 1
  fi
  CHECK_FILE=

  # Source Project Configuration
  export PTEK_PROJECT_KEY="$PROJECT_KEY"

  CHECK_FILE="${PTEK_APP_BASE}/lib/project_config.sh"
  if [[ -f $CHECK_FILE ]]; then
    source "$CHECK_FILE"
  else
    printf "ERROR: Project Config could not located at %s\n" "$CHECK_FILE"
    exit 1
  fi
  CHECK_FILE=

  # (Deprecated, sourcing auto-loads ptekprcfg and prjcfg())
  # Load project config once to get base_dir
  # project_config_load "${PROJECT_KEY}"

  # Resolve project root via canonical resolver
  PROJECT_REPO="$(prjcfg project_repo)"
  if [[ -z "${PROJECT_REPO}" ]]; then
    echo "ERROR: project_repo returned empty path for project '${PROJECT_KEY}'." >&2
    exit 2
  fi

  # Ensure logs directory
  mkdir -p "${PROJECT_REPO}/logs"
  export LOGFILE="${PROJECT_REPO}/logs/wordpress_deploy.log"

  # Bridge verbose flag
  if [[ "${VERBOSE}" == true ]]; then
    export PTEK_VERBOSE=1
  fi

}

# -----------------------------------------------------------------------------
# Load full project context
# -----------------------------------------------------------------------------

load_project_context() {

  info "Loading Project Context..."
  
  if [[ -z $(prjcfg project_key) ]]; then
    error "Project config has not been sourced"
    exit 1
  fi

  info "Setting Project Variables..."

  WORDPRESS_DIR="$(prjcfg 'project_repo')/wordpress"
  MANIFEST_FILE="${WORDPRESS_DIR}/.provisioned.json"

  PROJECT_TITLE="$(prjcfg 'project.title')"
  PROJECT_TITLE="${PROJECT_TITLE:-$PROJECT_KEY}"

  FRONTEND_NETWORK="$(prjcfg 'docker.frontend_network')"
  BACKEND_NETWORK="$(prjcfg 'docker.backend_network')"

  SQLDB_HOST="$(prjcfg 'database.host')"
  SQLDB_NAME="$(prjcfg 'database.name')"
  SQLDB_USER="$(prjcfg 'database.user')"
  SQLDB_PASSWORD="$(prjcfg 'database.pass')"

  WORDPRESS_HOST="$(prjcfg 'wordpress.host')"
  WORDPRESS_PORT="$(prjcfg 'wordpress.port')"
  WORDPRESS_SSL_PORT="$(prjcfg 'wordpress.ssl_port')"
  WORDPRESS_IMAGE="$(prjcfg 'wordpress.image')"
  WP_CLI_IMAGE="${WORDPRESS_IMAGE:-$WP_CLI_IMAGE_DEFAULT}"

  WORDPRESS_ADMIN_USER="$(prjcfg 'wordpress.admin_user')"
  WORDPRESS_ADMIN_EMAIL="$(prjcfg 'wordpress.admin_email')"
  WORDPRESS_ADMIN_PASSWORD="$(prjcfg 'wordpress.admin_password')"

  WORDPRESS_TABLE_PREFIX="$(prjcfg 'wordpress.table_prefix')"
  WORDPRESS_TABLE_PREFIX="${WORDPRESS_TABLE_PREFIX:-wp_}"

  info "Validating Project Variables..."

  # Validation
  [[ -z "${SQLDB_HOST}" || -z "${SQLDB_NAME}" || -z "${SQLDB_USER}" ]] &&
    { error "Database config incomplete"; exit 2; }

  [[ -z "${WORDPRESS_HOST}" ]] &&
    { error "wordpress.host missing"; exit 2; }

  [[ -z "${WORDPRESS_PORT}" && -z "${WORDPRESS_SSL_PORT}" ]] &&
    { error "wordpress.port or wordpress.ssl_port required"; exit 2; }

  [[ -z "${WORDPRESS_ADMIN_USER}" || -z "${WORDPRESS_ADMIN_EMAIL}" || -z "${WORDPRESS_ADMIN_PASSWORD}" ]] &&
    { error "Admin credentials incomplete"; exit 2; }

  success "Project Context loaded."

}

compute_wordpress_url() {
  if [[ -n "${WORDPRESS_SSL_PORT}" ]]; then
    WORDPRESS_URL="https://${WORDPRESS_HOST}:${WORDPRESS_SSL_PORT}"
  else
    WORDPRESS_URL="http://${WORDPRESS_HOST}:${WORDPRESS_PORT}"
  fi
}

# -----------------------------------------------------------------------------
# wp-cli runner
# -----------------------------------------------------------------------------

run_wp() {
  local wp_args=("$@")

  if [[ "${WHAT_IF}" == true ]]; then
    whatif "wp ${wp_args[*]}"
    return 0
  fi

  local docker_network="${BACKEND_NETWORK:-$FRONTEND_NETWORK}"
  [[ -z "${docker_network}" ]] && { error "No Docker network configured"; exit 2; }

  info "Running wp-cli via '${WP_CLI_IMAGE}' on network '${docker_network}'"

  docker run --rm \
    -v "${WORDPRESS_DIR}:/var/www/html" \
    --network "${docker_network}" \
    -e WORDPRESS_DB_HOST="${SQLDB_HOST}" \
    -e WORDPRESS_DB_USER="${SQLDB_USER}" \
    -e WORDPRESS_DB_PASSWORD="${SQLDB_PASSWORD}" \
    -e WORDPRESS_DB_NAME="${SQLDB_NAME}" \
    "${WP_CLI_IMAGE}" \
    wp "${wp_args[@]}"
}

# -----------------------------------------------------------------------------
# Provisioning steps
# -----------------------------------------------------------------------------

ensure_wordpress_directory() {
  if [[ -d "${WORDPRESS_DIR}" ]]; then
    info "WordPress directory exists"
  else
    [[ "${WHAT_IF}" == true ]] && { whatif "mkdir -p '${WORDPRESS_DIR}'"; return; }
    mkdir -p "${WORDPRESS_DIR}"
    info "Created ${WORDPRESS_DIR}"
  fi
}

provision_core() {
  local marker="${WORDPRESS_DIR}/wp-includes/version.php"

  if [[ -f "${marker}" ]]; then
    info "Core already present"
    MANIFEST_CORE=true
    return
  fi

  info "Downloading WordPress core..."
  run_wp core download --force

  if [[ -f "${marker}" || "${WHAT_IF}" == true ]]; then
    MANIFEST_CORE=true
  else
    error "Core download failed"
    exit 3
  fi
}

provision_config() {
  local cfg="${WORDPRESS_DIR}/wp-config.php"

  if [[ -f "${cfg}" ]]; then
    info "wp-config.php exists"
    MANIFEST_CONFIG=true
    return
  fi

  info "Generating wp-config.php..."

  run_wp config create \
    --dbname="${SQLDB_NAME}" \
    --dbuser="${SQLDB_USER}" \
    --dbpass="${SQLDB_PASSWORD}" \
    --dbhost="${SQLDB_HOST}" \
    --dbprefix="${WORDPRESS_TABLE_PREFIX}" \
    --skip-check \
    --force

  run_wp config shuffle-salts

  if [[ -f "${cfg}" || "${WHAT_IF}" == true ]]; then
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
    --url="${WORDPRESS_URL}" \
    --title="${PROJECT_TITLE}" \
    --admin_user="${WORDPRESS_ADMIN_USER}" \
    --admin_password="${WORDPRESS_ADMIN_PASSWORD}" \
    --admin_email="${WORDPRESS_ADMIN_EMAIL}"

  if [[ "${WHAT_IF}" == true ]]; then
    MANIFEST_INSTALLED=true
  elif run_wp core is-installed >/dev/null 2>&1; then
    MANIFEST_INSTALLED=true
  else
    error "Installation failed"
    exit 3
  fi
}

ensure_admin_user() {
  if run_wp user get "${WORDPRESS_ADMIN_USER}" >/dev/null 2>&1; then
    info "Admin user exists"
    MANIFEST_ADMIN=true
    return
  fi

  info "Creating admin user..."

  run_wp user create \
    "${WORDPRESS_ADMIN_USER}" \
    "${WORDPRESS_ADMIN_EMAIL}" \
    --user_pass="${WORDPRESS_ADMIN_PASSWORD}" \
    --role=administrator

  if [[ "${WHAT_IF}" == true ]]; then
    MANIFEST_ADMIN=true
  elif run_wp user get "${WORDPRESS_ADMIN_USER}" >/dev/null 2>&1; then
    MANIFEST_ADMIN=true
  else
    error "Admin user creation failed"
    exit 3
  fi
}

# -----------------------------------------------------------------------------
# Manifest
# -----------------------------------------------------------------------------

write_manifest() {
  if [[ "${WHAT_IF}" == true ]]; then
    whatif "Write manifest to '${MANIFEST_FILE}'"
    return
  fi

  cat > "${MANIFEST_FILE}" <<EOF
{
  "project": "${PROJECT_KEY}",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "core": ${MANIFEST_CORE},
  "config": ${MANIFEST_CONFIG},
  "installed": ${MANIFEST_INSTALLED},
  "admin_user": ${MANIFEST_ADMIN},
  "wordpress_url": "${WORDPRESS_URL}",
  "wordpress_dir": "${WORDPRESS_DIR}"
}
EOF

  info "Wrote manifest: ${MANIFEST_FILE}"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  parse_args "$@"
  bootstrap_config_and_logging

  log_header "WordPress deployment for '${PROJECT_KEY}'"
  info "WHAT_IF=${WHAT_IF} VERBOSE=${VERBOSE}"
  info "APP_BASE=${PTEK_APP_BASE}"

  load_project_context
  compute_wordpress_url

  info "Project root: ${PROJECT_REPO}"
  info "WordPress directory: ${WORDPRESS_DIR}"
  info "WordPress URL: ${WORDPRESS_URL}"
  info "wp-cli image: ${WP_CLI_IMAGE}"

  ensure_wordpress_directory
  provision_core
  provision_config
  install_wordpress
  ensure_admin_user
  write_manifest

  success "WordPress deployment completed for '${PROJECT_KEY}'."
}

main "$@"