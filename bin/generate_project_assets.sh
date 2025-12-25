#!/usr/bin/env bash
#==============================================================================
# generate_project_assets.sh
# --------------------------
# * Proxy Server assets
#   - Generate SSL Certificates to PROJECT_BASE/config/proxy/certs for
#     volume mount
#   - Deploy nginx.conf to PROJECT_BASE/config/proxy for volume mount
#==============================================================================
set -euo pipefail

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_KEY=""
CONFIG_BASE="$HOME/.ptekwpdev"
PROJECT_CONF="environments.json"
CERT_TOOL="openssl"
STATUS_ONLY=false
RENEW=false

if [[ -f "$APP_BASE/lib/output.sh" ]]; then 
    source "$APP_BASE/lib/output.sh" 
else 
    echo "Missing output.sh"
    exit 1 
fi
if [[ -f "$APP_BASE/lib/helpers.sh" ]]; then 
    source "$APP_BASE/lib/helpers.sh" 
else 
    echo "Missing helpers.sh"
    exit 1 
fi

usage() {
    echo "Usage: $(basename "$0") --project NAME [options]"
    echo "Options:"
    echo "  -p, --project NAME        REQUIRED project key"
    echo "  -c, --cert-tool TOOL      'openssl' (default) or 'mkcert'"
    echo "      --status              Check certs only"
    echo "      --renew               Force regeneration"
    echo "  -h, --help                Show this help"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--project) 
            PROJECT_KEY="$2"; 
            shift 2 
            ;;
        -c|--cert-tool) 
            CERT_TOOL="$2"; 
            shift 2 
            ;;
        --status) 
            STATUS_ONLY=true; 
            shift 
            ;;
        --renew) 
            RENEW=true; 
            shift 
            ;;
        -h|--help) 
            usage; 
            exit 0 
            ;;
        *) error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

[[ -z "$PROJECT_KEY" ]] && echo "Error: --project is required." && usage && exit 1

PROJECTS_FILE="$CONFIG_BASE/$PROJECT_CONF"
APP_PROJECT_BASE=$(jq -r '.app.project_base' "$PROJECTS_FILE" | sed "s|\$HOME|$HOME|")
PROJECT_CONFIG=$(jq -r --arg pr "$PROJECT_KEY" '.environments[$pr]' "$PROJECTS_FILE")
HOST_DOMAIN=$(echo "$PROJECT_CONFIG" | jq -r '.project_domain // empty')
BASE_DIR_REL=$(echo "$PROJECT_CONFIG" | jq -r '.base_dir // empty' | sed 's|^/||')
PROJECT_BASE="$APP_PROJECT_BASE/$BASE_DIR_REL"
WORDPRESS_HOST=$(echo "$PROJECT_CONFIG" | jq -r '.wordpress_host // empty')
PROJECT_NETWORK=$(echo "$PROJECT_CONFIG" | jq -r '.project_network // empty')

# After PROJECT_BASE is resolved
# Normalize logging output to project log file
LOG_DIR="$PROJECT_BASE/app/logs"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/generate_project_assets.log"

warn "Starting build for $PROJECT_KEY at $(date)"


PROXY_PATH="$PROJECT_BASE/config/proxy"
SSL_PATH="$PROXY_PATH/certs"
mkdir -p "$SSL_PATH"

CRT_FILE="$SSL_PATH/$HOST_DOMAIN.crt"
KEY_FILE="$SSL_PATH/$HOST_DOMAIN.key"

generate_ssl_certs() {
    # Status check
    if $STATUS_ONLY; then
        [[ -f "$CRT_FILE" && -f "$KEY_FILE" ]] && success "Certs exist for $PROJECT_KEY" && exit 0 || { error "No certs"; exit 1; }
    fi

    # Skip if exists
    if [[ -f "$CRT_FILE" && -f "$KEY_FILE" && $RENEW == false ]]; then
        success "Certs already exist. Use --renew to regenerate."
        exit 0
    fi

    # Generate
    case "$CERT_TOOL" in
        mkcert) mkcert -cert-file "$CRT_FILE" -key-file "$KEY_FILE" "$HOST_DOMAIN" ;;
        openssl) openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$KEY_FILE" -out "$CRT_FILE" -subj "/CN=$HOST_DOMAIN" ;;
        *) error "Unsupported cert tool"; exit 1 ;;
    esac

    success "Certificates generated for $PROJECT_KEY ($HOST_DOMAIN)."
}

generate_proxy_keys() {
    info "Generating proxy keys..."

    PROXY_DOMAIN="$HOST_DOMAIN"
    PROXY_UPSTREAM="$WORDPRESS_HOST"
    PROXY_NETWORK="$PROJECT_NETWORK"

    # Determine upstream port
    local wp_port
    local ssl_port

    wp_port=$(echo "$PROJECT_CONFIG" | jq -r '.wordpress_port // empty')
    ssl_port=$(echo "$PROJECT_CONFIG" | jq -r '.wordpress_ssl_port // empty')

    if [[ -n "$ssl_port" && "$ssl_port" != "null" ]]; then
        WORDPRESS_URL="${WORDPRESS_HOST}:${ssl_port}"
    else
        WORDPRESS_URL="${WORDPRESS_HOST}:${wp_port}"
    fi

    export PROXY_DOMAIN PROXY_UPSTREAM PROXY_NETWORK WORDPRESS_URL

    success "Proxy keys generated"
}

#
# Moves nginx proxy config template to PROJECT BASE from where
# it will be volumen mounted to /etc/nginx/conf.d/default.conf
#
copy_proxy_template() {
    ensure_dir "$PROJECT_BASE/config/proxy"
    cp "$CONFIG_BASE/config/proxy/default.conf.template" \
       "$PROJECT_BASE/config/proxy/default.conf.template"
    success "Copied proxy template into project"
}

generate_project_assets() {
    generate_ssl_certs
    generate_proxy_keys
    copy_proxy_template
}

# Final executor
generate_project_assets