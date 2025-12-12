#!/usr/bin/env bash
#
# Auto-install script for WordPress dev environments (ptekwpdev)
# - Centralized project lookup in ~/.ptekwpdev/environments.json
# - Uses PROJECT_BASE as context (templates generated during provisioning)
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
PROJECT_CONFIG_FILE="environments.json"
CONFIG_BASE="$HOME/.ptekwpdev"
PROJECT="default"

usage() {
    echo "Usage: $(basename "$0") [options]"
    echo "Options:"
    echo "  -p, --project NAME        Project name to look up in ~/.ptekwpdev/${PROJECT_CONFIG_FILE}"
    echo "  -h, --help                Show this help message"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--project) PROJECT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

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
# Project resolution
# -------------------------------
PROJECTS_FILE="$CONFIG_BASE/$PROJECT_CONFIG_FILE"

if [[ ! -f "$PROJECTS_FILE" ]]; then
    error "No project config found at $PROJECTS_FILE"
    exit 1
fi

PROJECT_CONFIG=$(jq -r --arg pr "$PROJECT" '.environments[$pr]' "$PROJECTS_FILE")
HOST_DOMAIN=$(echo "$PROJECT_CONFIG" | jq -r '.domain // empty')
PROJECT_BASE=$(echo "$PROJECT_CONFIG" | jq -r '.baseDir // empty')

if [[ -z "$PROJECT_BASE" || -z "$HOST_DOMAIN" ]]; then
    error "Project '$PROJECT' missing baseDir or domain in $PROJECTS_FILE"
    exit 1
fi

warn "Env Check: Project=$PROJECT Domain=$HOST_DOMAIN ProjectBase=$PROJECT_BASE"

# -------------------------------
# Auto-install logic
# -------------------------------
ENV_FILE="$PROJECT_BASE/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    error "Missing .env file at $ENV_FILE. Provisioning must generate it first."
    exit 1
fi

warn "Loading environment variables from $ENV_FILE"
set -a
source "$ENV_FILE"
set +a

# Example: run wp-cli inside container to finalize install
WP_CONTAINER="${PROJECT}_wp"

warn "Running WordPress auto-install in container: $WP_CONTAINER"
docker exec "$WP_CONTAINER" wp core install \
    --url="$WORDPRESS_DOMAIN" \
    --title="$WORDPRESS_PROJECT_TITLE" \
    --admin_user="$WORDPRESS_ADMIN_USER" \
    --admin_password="$WORDPRESS_ADMIN_PASS" \
    --admin_email="$WORDPRESS_ADMIN_EMAIL" \
    --skip-email

success "Auto-install completed for $PROJECT ($HOST_DOMAIN)"