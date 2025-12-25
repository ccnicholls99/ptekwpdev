#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------
# Load logging utilities
# ---------------------------------------------------------
APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_BASE="$HOME/.ptekwpdev"
PROJECT_CONF="$CONFIG_BASE/environments.json"

LOGFILE="/dev/null"  # no file logging until PROJECT_BASE is resolved
if [[ -f "$APP_BASE/lib/output.sh" ]]; then
    source "$APP_BASE/lib/output.sh"
else
    echo "Missing output.sh"
    exit 1
fi

# ---------------------------------------------------------
# Usage
# ---------------------------------------------------------
usage() {
    echo "Usage: $(basename "$0") --project KEY [--env]"
    echo ""
    echo "  -p, --project KEY     Project key from environments.json"
    echo "  -e, --env             Load PROJECT_BASE/docker/.env for overrides"
    echo "  -h, --help            Show help"
}

# ---------------------------------------------------------
# Parse args
# ---------------------------------------------------------
PROJECT=""
USE_ENV=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--project) PROJECT="$2"; shift 2 ;;
        -e|--env) USE_ENV=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

[[ -z "$PROJECT" ]] && error "--project is required" && exit 1

# ---------------------------------------------------------
# Load project configuration
# ---------------------------------------------------------
info "Loading configuration for project: $PROJECT"

PROJECT_CONFIG=$(jq -r --arg pr "$PROJECT" '.environments[$pr]' "$PROJECT_CONF")

if [[ "$PROJECT_CONFIG" == "null" ]]; then
    error "Project '$PROJECT' not found in $PROJECT_CONF"
fi

APP_PROJECT_BASE=$(jq -r '.app.project_base' "$PROJECT_CONF" | sed "s|\$HOME|$HOME|")
BASE_DIR_REL=$(echo "$PROJECT_CONFIG" | jq -r '.base_dir // empty' | sed 's|^/||')
PROJECT_BASE="$APP_PROJECT_BASE/$BASE_DIR_REL"

LOGFILE="$PROJECT_BASE/app/logs/healthcheck_proxy.log"  # Start file logging
mkdir -p "$PROJECT_BASE/app/logs/"

PROJECT_DOMAIN=$(echo "$PROJECT_CONFIG" | jq -r '.project_domain // empty')
WORDPRESS_HOST=$(echo "$PROJECT_CONFIG" | jq -r '.wordpress_host // empty')
WORDPRESS_PORT=$(echo "$PROJECT_CONFIG" | jq -r '.wordpress_port // empty')
WORDPRESS_SSL_PORT=$(echo "$PROJECT_CONFIG" | jq -r '.wordpress_ssl_port // empty')
PROJECT_NETWORK=$(echo "$PROJECT_CONFIG" | jq -r '.project_network // empty')

# ---------------------------------------------------------
# Optional: load .env overrides
# ---------------------------------------------------------
if $USE_ENV; then
    ENV_FILE="$PROJECT_BASE/docker/.env"
    if [[ -f "$ENV_FILE" ]]; then
        info "Loading environment overrides from $ENV_FILE"
        set -o allexport
        source "$ENV_FILE"
        set +o allexport
    else
        warn "No .env file found at $ENV_FILE — skipping"
    fi
fi

# ---------------------------------------------------------
# Resolve upstream port (SSL preferred)
# ---------------------------------------------------------
if [[ -n "${WORDPRESS_SSL_PORT:-}" && "$WORDPRESS_SSL_PORT" != "null" ]]; then
    UPSTREAM_PORT="$WORDPRESS_SSL_PORT"
else
    UPSTREAM_PORT="$WORDPRESS_PORT"
fi

WORDPRESS_URL="${WORDPRESS_HOST}:${UPSTREAM_PORT}"

# ---------------------------------------------------------
# Container name
# ---------------------------------------------------------
CONTAINER="${PROJECT}_proxy"

info "Resolved proxy container: $CONTAINER"
info "Resolved domain: $PROJECT_DOMAIN"
info "Resolved upstream: $WORDPRESS_URL"

# ---------------------------------------------------------
# 1. Check SSL certificates exist
# ---------------------------------------------------------
info "Checking SSL certificates inside container..."

docker exec "$CONTAINER" test -f "/etc/nginx/certs/${PROJECT_DOMAIN}.crt" \
    && docker exec "$CONTAINER" test -f "/etc/nginx/certs/${PROJECT_DOMAIN}.key" \
    && success "SSL certificates found" \
    || error "SSL certificates missing in /etc/nginx/certs"

# ---------------------------------------------------------
# 2. Validate Nginx configuration syntax
# ---------------------------------------------------------
info "Validating Nginx configuration syntax..."

docker exec "$CONTAINER" nginx -t >/dev/null 2>&1 \
    && success "Nginx configuration syntax is valid" \
    || abort "Nginx configuration syntax is INVALID"

# ---------------------------------------------------------
# 3. Check Nginx listening ports
# ---------------------------------------------------------
info "Checking Nginx listening ports..."

docker exec "$CONTAINER" sh -c "netstat -tln | grep ':80 '" >/dev/null \
    && success "Nginx is listening on port 80" \
    || warn "Nginx is NOT listening on port 80"

docker exec "$CONTAINER" sh -c "netstat -tln | grep ':443 '" >/dev/null \
    && success "Nginx is listening on port 443" \
    || warn "Nginx is NOT listening on port 443"

# ---------------------------------------------------------
# 4. Test HTTPS handshake
# ---------------------------------------------------------
info "Testing HTTPS handshake..."

docker exec "$CONTAINER" curl -skI "https://localhost" >/dev/null \
    && success "HTTPS handshake successful" \
    || abort "HTTPS handshake FAILED"

# ---------------------------------------------------------
# 5. Test upstream WordPress connectivity
# ---------------------------------------------------------
info "Testing upstream WordPress connectivity..."

docker exec "$CONTAINER" curl -s "http://${WORDPRESS_HOST}:${WORDPRESS_PORT}" >/dev/null \
    && success "Proxy can reach WordPress upstream (${WORDPRESS_HOST}:${WORDPRESS_PORT})" \
    || abort "Proxy CANNOT reach WordPress upstream"

# ---------------------------------------------------------
# Final summary
# ---------------------------------------------------------
success "Proxy container healthcheck PASSED"
exit 0