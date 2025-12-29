#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — WordPress Core Provisioning Script
#  Script: wordpress_deploy.sh
#
#  Synopsis:
#    Provision project-local WordPress core into PROJECT_REPO/wordpress using
#    project configuration loaded from CONFIG_BASE/config/projects.json.
#
#  Notes:
#    - Must be executed from APP_BASE/bin
#    - Uses project_config.sh for all project-level settings
#    - Never starts containers
#    - Never modifies CONFIG_BASE
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
# Resolve APP_BASE and load libraries
# ------------------------------------------------------------------------------

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "${APP_BASE}/lib/output.sh"
source "${APP_BASE}/lib/helpers.sh"
source "${APP_BASE}/lib/app_config.sh"
source "${APP_BASE}/lib/project_config.sh"

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------

set_log --truncate "$(appcfg app_log_dir)/wordpress_deploy.log" \
  "=== WordPress Deploy Run ($(date)) ==="

# ------------------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------------------

PROJECT=""
WHAT_IF=false

usage() {
  cat <<EOF
Usage: wordpress_deploy.sh --project <key> [-w]

Options:
  -p, --project <key>   Project key from projects.json
  -w, --what-if         Dry run (no changes applied)
  -h, --help            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project) PROJECT="$2"; shift 2 ;;
    -w|--what-if) WHAT_IF=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$PROJECT" ]]; then
  error "Missing required --project <key>"
  usage
  exit 1
fi

# ------------------------------------------------------------------------------
# Load project configuration
# ------------------------------------------------------------------------------

info "Loading configuration for project '${PROJECT}'"

project_config_load "$PROJECT"

PROJECT_REPO="$(prcfg project_repo)"
SQLDB_NAME="$(prcfg sqldb_name)"
SQLDB_USER="$(prcfg sqldb_user)"
SQLDB_PASS="$(prcfg sqldb_pass)"

if [[ -z "$PROJECT_REPO" ]]; then
  error "project_repo not resolved for project '${PROJECT}'"
  exit 1
fi

# ------------------------------------------------------------------------------
# Prepare paths
# ------------------------------------------------------------------------------

WORDPRESS_DIR="${PROJECT_REPO}/wordpress"
LOG_DIR="${PROJECT_REPO}/logs"

mkdir -p "$LOG_DIR"

set_log --append "${LOG_DIR}/wordpress_deploy.log" \
  "--- WordPress provisioning for project '${PROJECT}' ---"

info "Resolved PROJECT_REPO: ${PROJECT_REPO}"
info "WordPress directory: ${WORDPRESS_DIR}"

# ------------------------------------------------------------------------------
# Helper: run or preview
# ------------------------------------------------------------------------------

run_or_preview() {
  local msg="$1"
  shift
  if $WHAT_IF; then
    warn "[WHAT-IF] $msg"
    warn "[WHAT-IF] Command: $*"
  else
    info "$msg"
    "$@"
  fi
}

# ------------------------------------------------------------------------------
# Step 1: Create WordPress directory
# ------------------------------------------------------------------------------

if [[ ! -d "$WORDPRESS_DIR" ]]; then
  run_or_preview "Creating WordPress directory at $WORDPRESS_DIR" \
    mkdir -p "$WORDPRESS_DIR"
else
  warn "WordPress directory already exists — will not overwrite core"
fi

# ------------------------------------------------------------------------------
# Step 2: Download WordPress core (if missing)
# ------------------------------------------------------------------------------

if [[ ! -f "$WORDPRESS_DIR/wp-settings.php" ]]; then
  run_or_preview "Downloading WordPress core into $WORDPRESS_DIR" \
    wp core download --path="$WORDPRESS_DIR"
else
  warn "WordPress core already present — skipping download"
fi

# ------------------------------------------------------------------------------
# Step 3: Generate wp-config.php (if missing)
# ------------------------------------------------------------------------------

WP_CONFIG="${WORDPRESS_DIR}/wp-config.php"

if [[ ! -f "$WP_CONFIG" ]]; then
  info "Generating wp-config.php"

  run_or_preview "Creating wp-config.php" \
    wp config create \
      --path="$WORDPRESS_DIR" \
      --dbname="$SQLDB_NAME" \
      --dbuser="$SQLDB_USER" \
      --dbpass="$SQLDB_PASS" \
      --dbhost="${PROJECT}_sqldb" \
      --skip-check

  run_or_preview "Injecting salts" \
    wp config shuffle-salts --path="$WORDPRESS_DIR"

  success "wp-config.php created"
else
  warn "wp-config.php already exists — not regenerating"
fi

# ------------------------------------------------------------------------------
# Step 4: Ensure permissions
# ------------------------------------------------------------------------------

run_or_preview "Setting WordPress directory permissions" \
  chmod -R u+rwX,go+rX "$WORDPRESS_DIR"

success "WordPress provisioning complete for project '${PROJECT}'"
exit 0