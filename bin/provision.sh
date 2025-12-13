#!/usr/bin/env bash
#
# Provision script for WordPress dev environments (ptekwpdev)
# - Centralized project lookup in ~/.ptekwpdev/environments.json
# - Creates scaffold under PROJECT_BASE (app, bin, docker, src)
# - Shared output functions sourced from APP_BASE/lib/output.sh
#

set -euo pipefail

# -------------------------------
# Path resolution
# -------------------------------
APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# -------------------------------
# Defaults
# -------------------------------
PROJECT=""
CONFIG_BASE="$HOME/.ptekwpdev"
PROJECT_CONF="environments.json"

# -------------------------------
# Load helpers
# -------------------------------
if [[ -f "$APP_BASE/lib/output.sh" ]]; then
    # shellcheck disable=SC1091
    source "$APP_BASE/lib/output.sh"
else
    echo "Missing output.sh at $APP_BASE/lib/" >&2
    exit 1
fi

# -------------------------------
# Usage
# -------------------------------
usage() {
    echo "Usage: $(basename "$0") --project NAME"
    echo
    echo "Options:"
    echo "  -p, --project NAME        REQUIRED project key"
    echo "  -h, --help                Show this help message"
    echo
    echo "Example:"
    echo "  $(basename "$0") --project demo"
}

# -------------------------------
# Option parsing
# -------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--project) PROJECT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# -------------------------------
# Require project
# -------------------------------
if [[ -z "$PROJECT" ]]; then
    echo "Error: --project is required."
    usage
    exit 1
fi

# -------------------------------
# Project resolution
# -------------------------------
PROJECTS_FILE="$CONFIG_BASE/$PROJECT_CONF"

if [[ ! -f "$PROJECTS_FILE" ]]; then
    error "No project config found at $PROJECTS_FILE"
    exit 1
fi

APP_PROJECT_BASE=$(jq -r '.app.project_base' "$PROJECTS_FILE" | sed "s|\$HOME|$HOME|")
PROJECT_CONFIG=$(jq -r --arg pr "$PROJECT" '.environments[$pr]' "$PROJECTS_FILE")

HOST_DOMAIN=$(echo "$PROJECT_CONFIG" | jq -r '.domain // empty')
BASE_DIR_REL=$(echo "$PROJECT_CONFIG" | jq -r '.base_dir // empty' | sed 's|^/||')

PROJECT_BASE="$APP_PROJECT_BASE/$BASE_DIR_REL"

# After PROJECT_BASE is resolved
# Normalize logging output to project log file
LOG_DIR="$PROJECT_BASE/app/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/provision.log"
exec > >(tee -a "$LOG_FILE") 2>&1

warn "Starting build for $PROJECT at $(date)"

if [[ -z "$PROJECT_BASE" || -z "$HOST_DOMAIN" ]]; then
    error "Project '$PROJECT' missing base_dir or domain in $PROJECTS_FILE"
    exit 1
fi

warn "Provisioning project scaffold at $PROJECT_BASE"

# -------------------------------
# Scaffold directories
# -------------------------------
mkdir -p "$PROJECT_BASE"

for dir in app bin docker src; do
    mkdir -p "$PROJECT_BASE/$dir"
done

# Scaffold app/config structure
mkdir -p "$PROJECT_BASE/app/config/docker"
mkdir -p "$PROJECT_BASE/app/config/nginx"

# -------------------------------
# Initial files
# -------------------------------
ENV_FILE="$PROJECT_BASE/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    cat > "$ENV_FILE" <<EOF
WORDPRESS_DOMAIN=$HOST_DOMAIN
WORDPRESS_PROJECT_TITLE=$PROJECT
WORDPRESS_ADMIN_USER=admin
WORDPRESS_ADMIN_PASS=admin
WORDPRESS_ADMIN_EMAIL=admin@$HOST_DOMAIN
EOF
    success "Created .env file at $ENV_FILE"
else
    warn ".env file already exists at $ENV_FILE"
fi

success "Provisioning completed for $PROJECT ($HOST_DOMAIN)"