#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — App Bootstrap Script
#  Script: app_bootstrap.sh
#  Synopsis:
#    Establish the app-level configuration directory and generate app.json,
#    which contains all static app-level settings and secrets.
#
#  Description:
#    This script initializes the PTEKWPDEV application environment by creating
#    CONFIG_BASE, generating app.json with static configuration values, and
#    preparing the directory structure for runtime configuration files.
#
#    It does NOT:
#      - generate environments.json
#      - deploy Docker templates
#      - start containers
#
#    It is a pure initializer and must be run once after git clone.
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
# Resolve APP_BASE
# ------------------------------------------------------------------------------

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ------------------------------------------------------------------------------
# Load logging utilities
# ------------------------------------------------------------------------------

# shellcheck source=/dev/null
source "${APP_BASE}/lib/output.sh"

LOG_DIR="${APP_BASE}/app/logs"
mkdir -p "${LOG_DIR}"

set_log --truncate "${LOG_DIR}/app_bootstrap.log" \
  "=== App Bootstrap Run ($(date)) ==="

# ------------------------------------------------------------------------------
# Determine CONFIG_BASE and PROJECT_BASE
# ------------------------------------------------------------------------------

CONFIG_BASE="${HOME}/.ptekwpdev"
PROJECT_BASE="${HOME}/projects"

mkdir -p "${CONFIG_BASE}"
mkdir -p "${PROJECT_BASE}"

info "APP_BASE:     ${APP_BASE}"
info "CONFIG_BASE:  ${CONFIG_BASE}"
info "PROJECT_BASE: ${PROJECT_BASE}"

# ------------------------------------------------------------------------------
# Generate secrets
# ------------------------------------------------------------------------------

generate_secret() {
  head -c 64 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 32
}

SQDB_ROOT_PASS="$(generate_secret)"
SQDB_ROOT_USER="root"

# ------------------------------------------------------------------------------
# Generate app.json in APP_BASE, ready to be deployed to CONFIG_BASE
# ------------------------------------------------------------------------------

APP_JSON="${APP_BASE}/app/config/app.json"

info "Generating app.json → ${APP_JSON}"

cat > "${APP_JSON}" <<EOF
{
  "app_key": "ptekwpdev",
  "app_base": "${APP_BASE}",
  "config_base": "${CONFIG_BASE}",
  "project_base": "${PROJECT_BASE}",

  "backend_network": "ptekwpdev_backend",

  "secrets": {
    "sqldb_root": "${SQDB_ROOT_USER}",
    "sqldb_root_pass": "${SQDB_ROOT_PASS}"
  },

  "database": {
    "sqldb_port": "3306",
    "sqldb_image": "mariadb:10.11",
    "sqldb_version": "10.5",

    "sqladmin_image": "phpmyadmin/phpmyadmin",
    "sqladmin_version": "latest",
    "sqladmin_port": "5211"
  },

  "assets": {
    "container": "ptekwpdev_assets",
    "root_path": "/usr/src/ptekwpdev/assets"
  },

  "wordpress_defaults": {
    "image": "wordpress:latest",
    "php_version": "8.2",
    "port": 8080,
    "ssl_port": 8443
  }
}
EOF

success "app.json created at ${APP_JSON}"

# ------------------------------------------------------------------------------
# Validate JSON
# ------------------------------------------------------------------------------

if ! jq empty "${APP_JSON}" >/dev/null 2>&1; then
  error "Generated app.json is invalid JSON"
  exit 1
fi

success "app.json validated"

# ------------------------------------------------------------------------------
# Prepare CONFIG_BASE directory structure
# ------------------------------------------------------------------------------

info "Preparing CONFIG_BASE directory structure"

mkdir -p "${CONFIG_BASE}/config"
mkdir -p "${CONFIG_BASE}/docker"
mkdir -p "${CONFIG_BASE}/config/proxy"
mkdir -p "${CONFIG_BASE}/config/wordpress"
mkdir -p "${CONFIG_BASE}/config/php"

info "Copying app.json into $CONFIG_BASE/config"
cp "$APP_BASE/app/config/app.json" "$CONFIG_BASE/config"

success "CONFIG_BASE initialized"

# ------------------------------------------------------------------------------
# Done
# ------------------------------------------------------------------------------

success "App bootstrap complete."