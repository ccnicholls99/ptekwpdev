#!/bin/bash
# Generate or check SSL certificates for WordPress dev environments (ptekwpdev)

set -euo pipefail

# -------------------------------
# Path resolution
# -------------------------------
APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# -------------------------------
# Defaults & CLI Arguments
# -------------------------------
PROJECT="default"
CERT_TOOL="openssl"   # options: openssl | mkcert
CONFIG_BASE="$HOME/.ptekwpdev"
PROJECT_CONF="environments.json"
STATUS_ONLY=false
RENEW=false

usage() {
    echo "Usage: $(basename "$0") [options]"
    echo "Options:"
    echo "  -p, --project NAME        Project name to look up in ~/.ptekwpdev/${PROJECT_CONF}"
    echo "  -c, --cert-tool TOOL      Certificate tool: 'openssl' (default) or 'mkcert'"
    echo "      --status              Check if certs exist for project, do not regenerate"
    echo "      --renew               Force regeneration even if certs already exist"
    echo "  -h, --help                Show this help message"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--project) PROJECT="$2"; shift 2 ;;
        -c|--cert-tool) CERT_TOOL="$2"; shift 2 ;;
        --status) STATUS_ONLY=true; shift ;;
        --renew) RENEW=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# -------------------------------
# Load helpers & environment
# -------------------------------
if [[ -f "$APP_BASE/lib/output.sh" ]]; then
    # shellcheck disable=SC1091
    source "$APP_BASE/lib/output.sh"
else
    echo "Missing output helpers: $APP_BASE/lib/output.sh" >&2
    exit 1
fi

# Resolve domain and project base from environments.json
PROJECTS_FILE="$CONFIG_BASE/$PROJECT_CONF"
if [[ ! -f "$PROJECTS_FILE" ]]; then
    error "No project config found at $PROJECTS_FILE"
    exit 1
fi

PROJECT_CONFIG=$(jq -r --arg pr "$PROJECT" '.environments[$pr]' "$PROJECTS_FILE")
HOST_DOMAIN=$(echo "$PROJECT_CONFIG" | jq -r '.domain // empty')
PROJECT_BASE=$(echo "$PROJECT_CONFIG" | jq -r '.baseDir // empty')

if [[ -z "$HOST_DOMAIN" || -z "$PROJECT_BASE" ]]; then
    error "Project '$PROJECT' missing domain or baseDir in $PROJECTS_FILE"
    exit 1
fi

warn "Env Check: Project=$PROJECT Domain=$HOST_DOMAIN BaseDir=$PROJECT_BASE"

# -------------------------------
# Paths
# -------------------------------
PROXY_PATH="$PROJECT_BASE/docker/config/proxy"
SSL_PATH="$PROJECT_BASE/docker/config/ssl"
CERTS_PATH="$PROXY_PATH/certs"
mkdir -p "$PROXY_PATH" "$SSL_PATH" "$CERTS_PATH"

CRT_FILE="$CERTS_PATH/$HOST_DOMAIN.crt"
KEY_FILE="$CERTS_PATH/$HOST_DOMAIN.key"

# -------------------------------
# Status mode
# -------------------------------
if $STATUS_ONLY; then
    if [[ -f "$CRT_FILE" && -f "$KEY_FILE" ]]; then
        success "Valid certs exist for $PROJECT ($HOST_DOMAIN):"
        ls -l "$CRT_FILE" "$KEY_FILE"
        exit 0
    else
        error "No valid certs found for $PROJECT ($HOST_DOMAIN)."
        exit 1
    fi
fi

# -------------------------------
# Skip regeneration if certs exist (unless --renew)
# -------------------------------
if [[ -f "$CRT_FILE" && -f "$KEY_FILE" && $RENEW == false ]]; then
    success "Certs already exist for $PROJECT ($HOST_DOMAIN). Use --renew to force regeneration."
    exit 0
fi

# -------------------------------
# SSL Config
# -------------------------------
warn "Updating SSL Config..."
cp -u "$SSL_PATH/ssl.conf.tpl" "$SSL_PATH/ssl.conf"
sed -i "s/\${PROJECT_DOMAIN}/$HOST_DOMAIN/g" "$SSL_PATH/ssl.conf"

# -------------------------------
# NGINX Config
# -------------------------------
warn "Generating new proxy config..."
rm -f "$PROXY_PATH/nginx.conf"
local_wp_url="http://${WORDPRESS_HOST:-localhost}:${WORDPRESS_PORT:-80}"
cp "$PROXY_PATH/nginx.conf.tpl" "$PROXY_PATH/nginx.conf"
sed -i "s/\${PROJECT_DOMAIN}/$HOST_DOMAIN/g" "$PROXY_PATH/nginx.conf"
sed -i "s|\${WORDPRESS_URL}|$local_wp_url|g" "$PROXY_PATH/nginx.conf"

# -------------------------------
# Certificate Generation
# -------------------------------
case "$CERT_TOOL" in
    mkcert)
        warn "Using mkcert for certs..."
        mkcert -cert-file "$CRT_FILE" -key-file "$KEY_FILE" "$HOST_DOMAIN"
        ;;
    openssl)
        warn "Using OpenSSL for certs..."
        openssl req -x509 -nodes -days 365 \
            -newkey rsa:2048 \
            -keyout "$KEY_FILE" \
            -out "$CRT_FILE" \
            -config "$SSL_PATH/ssl.conf" \
            -extensions 'v3_req'

        warn "Installing cert into system trust store..."
        sudo cp -u "$CRT_FILE" /usr/local/share/ca-certificates/
        sudo update-ca-certificates
        ;;
    *)
        error "Unsupported cert tool: $CERT_TOOL"
        exit 1
        ;;
esac

# -------------------------------
# Post-generation verification
# -------------------------------
if [[ ! -f "$CRT_FILE" || ! -f "$KEY_FILE" ]]; then
    error "Certificate generation failed: missing .crt or .key file in $CERTS_PATH"
    exit 1
fi

success "Certificates generated, verified, and proxy config updated."