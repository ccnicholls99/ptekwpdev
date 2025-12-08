#!/usr/bin/env bash
set -euo pipefail

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_BASE="${HOME}/.ptekwpdev"
CONFIG_FILE="${CONFIG_BASE}/environments.json"

# Source logging
if [[ -f "${APP_BASE}/lib/output.sh" ]]; then
  # shellcheck disable=SC1091
  source "${APP_BASE}/lib/output.sh"
else
  echo "[ERR] Missing lib/output.sh at ${APP_BASE}/lib/output.sh" >&2
  exit 1
fi

PROJECT_NAME=""

usage() {
  echo "Usage: $0 [--project <name>]"
  exit 1
}

# === Option parsing ===
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT_NAME="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) shift ;;
  esac
done

# === Validate config ===
[[ -f "$CONFIG_FILE" ]] || { error "Missing config file: $CONFIG_FILE"; exit 1; }

PROJECT_BASE=$(jq -r '.app.project_base' "$CONFIG_FILE")
JSON_PROJECT_NAME=$(jq -r '.environments.project_name' "$CONFIG_FILE")
JSON_DOMAIN=$(jq -r '.environments.domain' "$CONFIG_FILE")

PROJECT_NAME="${PROJECT_NAME:-$JSON_PROJECT_NAME}"

TARGET_ROOT="${PROJECT_BASE}/${PROJECT_NAME}"
DOCKER_DEST="${TARGET_ROOT}/docker"
CONFIG_DEST="${DOCKER_DEST}/config"

info "Provisioning project: $PROJECT_NAME at $TARGET_ROOT"

# === Secrets from JSON ===
SQLDB_NAME=$(jq -r '.environments.secrets.sqldb_name' "$CONFIG_FILE")
SQLDB_USER=$(jq -r '.environments.secrets.sqldb_user' "$CONFIG_FILE")
SQLDB_PASS=$(jq -r '.environments.secrets.sqldb_pass' "$CONFIG_FILE")
SQLDB_ROOT_PASS=$(jq -r '.environments.secrets.sqldb_root_pass' "$CONFIG_FILE")
WP_ADMIN_USER=$(jq -r '.environments.secrets.wp_admin_user' "$CONFIG_FILE")
WP_ADMIN_PASS=$(jq -r '.environments.secrets.wp_admin_pass' "$CONFIG_FILE")
WP_ADMIN_EMAIL=$(jq -r '.environments.secrets.wp_admin_email' "$CONFIG_FILE")
JWT_SECRET=$(jq -r '.environments.secrets.jwt_secret' "$CONFIG_FILE")

# === Generate .env from env.tpl using Bash substitution ===
generate_env_file() {
  local tpl="$1"
  local dest="$2"
  local content
  content=$(<"$tpl")

  content="${content//^SQLDB_NAME^/$SQLDB_NAME}"
  content="${content//^SQLDB_USER^/$SQLDB_USER}"
  content="${content//^SQLDB_PASS^/$SQLDB_PASS}"
  content="${content//^SQLDB_ROOT_PASS^/$SQLDB_ROOT_PASS}"
  content="${content//^WP_ADMIN_USER^/$WP_ADMIN_USER}"
  content="${content//^WP_ADMIN_PASS^/$WP_ADMIN_PASS}"
  content="${content//^WP_ADMIN_EMAIL^/$WP_ADMIN_EMAIL}"
  content="${content//^JWT_SECRET^/$JWT_SECRET}"

  printf "%s\n" "$content" > "$dest"
}

# === Provision directories ===
ensure_dir "$CONFIG_DEST/apache"

for service in wordpress sqldb sqladmin proxy wpcli; do
  ensure_dir "$CONFIG_DEST/$service"
  cp -r "${CONFIG_BASE}/config/${service}/"* "$CONFIG_DEST/$service/" 2>/dev/null || true
done

# Copy docker base files
ensure_dir "$DOCKER_DEST"
if [[ -f "${CONFIG_BASE}/config/docker/env.tpl" ]]; then
  generate_env_file "${CONFIG_BASE}/config/docker/env.tpl" "${DOCKER_DEST}/.env"
  success ".env generated"
fi

# Scaffold fixed files
touch "${CONFIG_DEST}/wordpress.Dockerfile"
touch "${CONFIG_DEST}/compose.build.yml"
touch "${CONFIG_DEST}/.dockerignore"

success "Provisioning complete for project: $PROJECT_NAME"