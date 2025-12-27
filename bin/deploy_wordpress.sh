#!/usr/bin/env bash
# ================================================================================
# PTEKWPDEV — a multi-project, bootstrap app for localized WordPress development
# github: https://github.com/ccnicholls99/ptekwpdev.git
# ------------------------------------------------------------------------------
# Script: deploy_wordpress.sh
#
# Description:
#   WordPress Core Provisioning Script
#   Provision project-local WordPress core into
#   PROJECT_BASE/wordpress using explicit config
#   from CONFIG_BASE/environments.json
#
# Notes:
#   
#
# ================================================================================
set -euo pipefail

# Resolve APP_BASE relative to this script
APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load logging + helpers
source "${APP_BASE}/lib/output.sh"
source "${APP_BASE}/lib/helpers.sh"

set_log "$APP_BASE/app/logs/deply_wordpress.log" "+--- Starting WORDPRESS deployment"

# Paths
CONFIG_BASE="${APP_BASE}/config"
ENVIRONMENTS_JSON="${CONFIG_BASE}/environments.json"

PROJECT_KEY=""
WHAT_IF=false

usage() {
  echo "Usage: $0 -p <project>"
  echo "Options:"
  echo "  -p, --project <key>   Project key from environments.json"
  echo "  -w, --what-if         Dry run (no changes applied)"
  echo "  -h, --help            Show this help"
  exit 1
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project)
      PROJECT_KEY="$2"
      shift 2
      ;;
    -w|--what-if)
      WHAT_IF=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      error "Unknown option: $1"
      usage
      ;;
  esac
done

if [[ -z "$PROJECT_KEY" ]]; then
  error "Missing required --project option"
  usage
fi

# ------------------------------------------------------------
# Load project configuration
# ------------------------------------------------------------

info "Loading configuration for project: $PROJECT_KEY"

PROJECT_BASE=$(jq -r --arg p "$PROJECT_KEY" '.[$p].PROJECT_BASE' "$ENVIRONMENTS_JSON")
PROJECT_DOMAIN=$(jq -r --arg p "$PROJECT_KEY" '.[$p].PROJECT_DOMAIN' "$ENVIRONMENTS_JSON")
SQLDB_NAME=$(jq -r --arg p "$PROJECT_KEY" '.[$p].SQLDB_NAME' "$ENVIRONMENTS_JSON")
SQLDB_USER=$(jq -r --arg p "$PROJECT_KEY" '.[$p].SQLDB_USER' "$ENVIRONMENTS_JSON")
SQLDB_PASSWORD=$(jq -r --arg p "$PROJECT_KEY" '.[$p].SQLDB_PASSWORD' "$ENVIRONMENTS_JSON")

if [[ "$PROJECT_BASE" == "null" ]]; then
  error "Project '$PROJECT_KEY' not found in environments.json"
  exit 1
fi
set_log "$PROJECT_BASE/app/logs/deply_wordpress.log" "+--- Starting WORDPRESS deployment"

WORDPRESS_DIR="${PROJECT_BASE}/wordpress"

info "Resolved PROJECT_BASE: $PROJECT_BASE"
info "Resolved WordPress directory: $WORDPRESS_DIR"

# ------------------------------------------------------------
# Helper: run or preview
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# Step 1: Create WordPress directory
# ------------------------------------------------------------
if [[ ! -d "$WORDPRESS_DIR" ]]; then
  run_or_preview "Creating WordPress directory at $WORDPRESS_DIR" \
    mkdir -p "$WORDPRESS_DIR"
else
  warn "WordPress directory already exists — will not overwrite core"
fi

# ------------------------------------------------------------
# Step 2: Download WordPress core (if missing)
# ------------------------------------------------------------
if [[ ! -f "$WORDPRESS_DIR/wp-settings.php" ]]; then
  run_or_preview "Downloading WordPress core into $WORDPRESS_DIR" \
    wp core download --path="$WORDPRESS_DIR"
else
  warn "WordPress core already present — skipping download"
fi

# ------------------------------------------------------------
# Step 3: Generate wp-config.php (if missing)
# ------------------------------------------------------------
WP_CONFIG="${WORDPRESS_DIR}/wp-config.php"

if [[ ! -f "$WP_CONFIG" ]]; then
  info "Generating wp-config.php"

  run_or_preview "Creating wp-config.php" \
    wp config create \
      --path="$WORDPRESS_DIR" \
      --dbname="$SQLDB_NAME" \
      --dbuser="$SQLDB_USER" \
      --dbpass="$SQLDB_PASSWORD" \
      --dbhost="${PROJECT_KEY}_sqldb" \
      --skip-check

  run_or_preview "Injecting salts" \
    wp config shuffle-salts --path="$WORDPRESS_DIR"

  success "wp-config.php created"
else
  warn "wp-config.php already exists — not regenerating"
fi

# ------------------------------------------------------------
# Step 4: Ensure permissions
# ------------------------------------------------------------
run_or_preview "Setting WordPress directory permissions" \
  chmod -R u+rwX,go+rX "$WORDPRESS_DIR"

success "WordPress provisioning complete for project '$PROJECT_KEY'"