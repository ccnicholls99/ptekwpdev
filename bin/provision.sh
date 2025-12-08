#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="${HOME}/.ptekwpdev"
CONFIG_FILE="${WORKSPACE_ROOT}/workspaces.json"

VERBOSE=1

usage() {
  echo "Usage: $0 [-q|--quiet] [-d|--debug] <workspace-name>"
  exit 1
}

# === Unified option loop ===
while [[ $# -gt 0 ]]; do
  case "$1" in
    -q|--quiet) VERBOSE=0; shift ;;
    -d|--debug) VERBOSE=2; shift ;;
    -h|--help)  usage ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      ;;
    *)
      WORKSPACE_NAME="$1"
      shift
      ;;
  esac
done

if [[ -z "${WORKSPACE_NAME:-}" ]]; then
  echo "Error: workspace name required"
  usage
fi

export VERBOSE
source "$(dirname "$0")/lib/output.sh"

# === Validate config ===
if [[ ! -f "$CONFIG_FILE" ]]; then
  error "Missing config file: $CONFIG_FILE"
  exit 1
fi

if ! jq -e --arg ws "$WORKSPACE_NAME" '.workspaces[$ws]' "$CONFIG_FILE" >/dev/null; then
  error "Workspace '$WORKSPACE_NAME' not found in config"
  exit 1
fi

info "Provisioning workspace: $WORKSPACE_NAME"

# === Read values from config ===
DOMAIN=$(jq -r --arg ws "$WORKSPACE_NAME" '.workspaces[$ws].domain' "$CONFIG_FILE")
DB_NAME=$(jq -r --arg ws "$WORKSPACE_NAME" '.workspaces[$ws].db_name' "$CONFIG_FILE")
DB_USER=$(jq -r --arg ws "$WORKSPACE_NAME" '.workspaces[$ws].db_user' "$CONFIG_FILE")
PLUGINS=$(jq -r --arg ws "$WORKSPACE_NAME" '.workspaces[$ws].plugins[]?' "$CONFIG_FILE")
THEME=$(jq -r --arg ws "$WORKSPACE_NAME" '.workspaces[$ws].theme' "$CONFIG_FILE")

DB_PASS_FILE=$(jq -r --arg ws "$WORKSPACE_NAME" '.workspaces[$ws].secrets.db_pass_file' "$CONFIG_FILE")

PROJECTS_DIR=$(jq -r '.app.projects_dir' "$CONFIG_FILE")
ASSETS_DIR=$(jq -r '.app.assets_dir' "$CONFIG_FILE")
CERTS_DIR=$(jq -r '.app.certs_dir' "$CONFIG_FILE")
DB_IMAGE=$(jq -r '.app.db_image' "$CONFIG_FILE")
WP_IMAGE=$(jq -r '.app.wp_image' "$CONFIG_FILE")

WORKSPACE_DIR="${PROJECTS_DIR}/${WORKSPACE_NAME}"

# === Ensure directories ===
ensure_dir "$WORKSPACE_DIR"
ensure_dir "$ASSETS_DIR"
ensure_dir "$CERTS_DIR"

# === Generate SSL cert if missing ===
CERT_PATH="${CERTS_DIR}/${DOMAIN}"
ensure_dir "$CERT_PATH"
if [[ ! -f "${CERT_PATH}/cert.pem" ]]; then
  info "Generating SSL cert for $DOMAIN"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "${CERT_PATH}/key.pem" \
    -out "${CERT_PATH}/cert.pem" \
    -subj "/CN=${DOMAIN}"
  success "SSL cert created at ${CERT_PATH}"
else
  warn "SSL cert already exists for $DOMAIN"
fi

# === Scaffold docker-compose.yml ===
COMPOSE_FILE="${WORKSPACE_DIR}/docker-compose.yml"
if [[ ! -f "$COMPOSE_FILE" ]]; then
  info "Generating docker-compose.yml for $WORKSPACE_NAME"
  cat > "$COMPOSE_FILE" <<EOF
version: '3.9'
services:
  db:
    image: ${DB_IMAGE}
    environment:
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD_FILE: ${DB_PASS_FILE}
    volumes:
      - ${WORKSPACE_DIR}/db_data:/var/lib/mysql

  wordpress:
    image: ${WP_IMAGE}
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_NAME: ${DB_NAME}
      WORDPRESS_DB_USER: ${DB_USER}
      WORDPRESS_DB_PASSWORD_FILE: ${DB_PASS_FILE}
    volumes:
      - ${WORKSPACE_DIR}/wp_data:/var/www/html
      - ${ASSETS_DIR}:/var/www/html/wp-content/uploads
    ports:
      - "8080:80"

  phpmyadmin:
    image: phpmyadmin/phpmyadmin
    environment:
      PMA_HOST: db
    ports:
      - "8081:80"
EOF
  success "docker-compose.yml created at ${COMPOSE_FILE}"
else
  warn "docker-compose.yml already exists for $WORKSPACE_NAME"
fi

# === Plugin/theme scaffolding (placeholder) ===
info "Workspace plugins: $PLUGINS"
info "Workspace theme: $THEME"

success "Provisioning complete for workspace: $WORKSPACE_NAME"