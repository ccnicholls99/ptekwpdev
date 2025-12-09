#!/usr/bin/env bash
set -euo pipefail

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_BASE="${HOME}/.ptekwpdev"
CONFIG_FILE="${CONFIG_BASE}/environments.json"

source "${APP_BASE}/lib/output.sh"
source "${APP_BASE}/lib/helpers.sh"

PROJECT_KEY=""

usage() {
  echo "Usage: $0 --project <key>"
  exit 1
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT_KEY="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) error "Unknown option: $1"; usage ;;
  esac
done

[[ -n "$PROJECT_KEY" ]] || { error "Missing --project"; usage; }
[[ -f "$CONFIG_FILE" ]] || { error "Missing config file: $CONFIG_FILE"; exit 1; }

PROJECT_NAME=$(jq -r ".environments[\"$PROJECT_KEY\"].project_name" "$CONFIG_FILE")
PROJECT_DOMAIN=$(jq -r ".environments[\"$PROJECT_KEY\"].domain" "$CONFIG_FILE")
PROJECT_BASE=$(jq -r '.app.project_base' "$CONFIG_FILE")
PROJECT_BASE="${PROJECT_BASE/\$HOME/$HOME}"

TARGET_ROOT="${PROJECT_BASE}/${PROJECT_NAME}"
CONFIG_DEST="${TARGET_ROOT}/config"
SSL_DEST="${CONFIG_DEST}/ssl"
PROXY_DEST="${CONFIG_DEST}/proxy"

ensure_dir "$CONFIG_DEST"
ensure_dir "$SSL_DEST"
ensure_dir "$PROXY_DEST"

CERT_FILE="${SSL_DEST}/${PROJECT_DOMAIN}.crt"
KEY_FILE="${SSL_DEST}/${PROJECT_DOMAIN}.key"

# Generate cert/key if missing
if [[ ! -f "$CERT_FILE" || ! -f "$KEY_FILE" ]]; then
  info "Generating dev SSL certificate for ${PROJECT_DOMAIN}"
  openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -subj "/CN=${PROJECT_DOMAIN}"
  success "Dev SSL cert/key generated at ${SSL_DEST}"
else
  warn "SSL cert/key already exist for ${PROJECT_DOMAIN}, skipping generation"
fi

# Copy proxy configs from canonical templates
cp -r "${APP_BASE}/config/proxy/"* "$PROXY_DEST/" 2>/dev/null || true

# Replace caret tokens in copied proxy configs
for f in "$PROXY_DEST"/*; do
  [[ -f "$f" ]] || continue
  # Use portable token replacement (caret-style)
  sed -i "s|^project_domain^|${PROJECT_DOMAIN}|g" "$f"
  sed -i "s|^ssl_cert^|${CERT_FILE}|g" "$f"
  sed -i "s|^ssl_key^|${KEY_FILE}|g" "$f"
done

success "Proxy configs prepared at ${PROXY_DEST}"