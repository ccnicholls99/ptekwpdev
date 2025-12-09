#!/usr/bin/env bash
set -euo pipefail

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_BASE="${HOME}/.ptekwpdev"
CONFIG_FILE="${CONFIG_BASE}/environments.json"

# Must run from APP_BASE
if [[ "$PWD" != "$APP_BASE" ]]; then
  echo "[ERR] Must run from APP_BASE: $APP_BASE"
  echo "      Current directory: $PWD"
  exit 1
fi

mkdir -p "${CONFIG_BASE}"

LOG_FILE="${CONFIG_BASE}/add-project.log"
source "${APP_BASE}/lib/output.sh"
source "${APP_BASE}/lib/helpers.sh"

PROJECT_KEY=""
PROJECT_TITLE=""
PROJECT_DOMAIN=""

usage() {
  echo "Usage: $0 --project <key> --name <title> --domain <domain>"
  exit 1
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT_KEY="$2"; shift 2 ;;
    --name) PROJECT_TITLE="$2"; shift 2 ;;
    --domain) PROJECT_DOMAIN="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) error "Unknown option: $1"; usage ;;
  esac
done

# Validate
if [[ -z "$PROJECT_KEY" || -z "$PROJECT_TITLE" || -z "$PROJECT_DOMAIN" ]]; then
  error "Missing required arguments"
  usage
fi

# Check if project key already exists
if jq -e ".environments | has(\"$PROJECT_KEY\")" "$CONFIG_FILE" >/dev/null; then
  error "Project key '$PROJECT_KEY' already exists in $CONFIG_FILE"
  exit 1
fi

PROJECT_NAME="$PROJECT_KEY"

# === Call backup utility from helpers.sh ===
backup_config "$CONFIG_FILE"

info "Adding project [$PROJECT_KEY] → name: $PROJECT_NAME, title: $PROJECT_TITLE, domain: $PROJECT_DOMAIN"

tmpfile="$(mktemp)"
jq --arg key "$PROJECT_KEY" \
   --arg name "$PROJECT_NAME" \
   --arg title "$PROJECT_TITLE" \
   --arg domain "$PROJECT_DOMAIN" \
   '.environments[$key] = {
      "project_name": $name,
      "project_title": $title,
      "description": "Development environment for " + $title,
      "baseDir": "/ptekwpdev/" + $key,
      "domain": $domain,
      "secrets": {
        "project_domain": $domain,
        "sqldb_name": $key + "db",
        "sqldb_user": $key + "dbu",
        "sqldb_pass": "ChangeMe1!",
        "sqldb_root_pass": "ChangeMe1!",
        "wp_admin_user": "admin",
        "wp_admin_pass": "ChangeMe1!",
        "wp_admin_email": "admin@" + $domain,
        "jwt_secret": "1234567890!@#$%^&*()"
      }
    }' "$CONFIG_FILE" > "$tmpfile" && mv "$tmpfile" "$CONFIG_FILE"

success "Project [$PROJECT_KEY] added to $CONFIG_FILE"