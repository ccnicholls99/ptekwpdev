#!/usr/bin/env bash
set -euo pipefail

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT=""
CONFIG_BASE="$HOME/.ptekwpdev"
PROJECT_CONF="environments.json"
CERT_TOOL="openssl"
STATUS_ONLY=false
RENEW=false

if [[ -f "$APP_BASE/lib/output.sh" ]]; then source "$APP_BASE/lib/output.sh"; else echo "Missing output.sh"; exit 1; fi

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
        -p|--project) PROJECT="$2"; shift 2 ;;
        -c|--cert-tool) CERT_TOOL="$2"; shift 2 ;;
        --status) STATUS_ONLY=true; shift ;;
        --renew) RENEW=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

[[ -z "$PROJECT" ]] && echo "Error: --project is required." && usage && exit 1

PROJECTS_FILE="$CONFIG_BASE/$PROJECT_CONF"
APP_PROJECT_BASE=$(jq -r '.app.project_base' "$PROJECTS_FILE" | sed "s|\$HOME|$HOME|")
PROJECT_CONFIG=$(jq -r --arg pr "$PROJECT" '.environments[$pr]' "$PROJECTS_FILE")
HOST_DOMAIN=$(echo "$PROJECT_CONFIG" | jq -r '.domain // empty')
BASE_DIR_REL=$(echo "$PROJECT_CONFIG" | jq -r '.base_dir // empty' | sed 's|^/||')
PROJECT_BASE="$APP_PROJECT_BASE/$BASE_DIR_REL"

# After PROJECT_BASE is resolved
# Normalize logging output to project log file
LOG_DIR="$PROJECT_BASE/app/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/generate_certs.log"
exec > >(tee -a "$LOG_FILE") 2>&1

warn "Starting build for $PROJECT at $(date)"


PROXY_PATH="$PROJECT_BASE/docker/config/proxy"
SSL_PATH="$PROJECT_BASE/docker/config/ssl"
CERTS_PATH="$PROXY_PATH/certs"
mkdir -p "$CERTS_PATH"

CRT_FILE="$CERTS_PATH/$HOST_DOMAIN.crt"
KEY_FILE="$CERTS_PATH/$HOST_DOMAIN.key"

# Status check
if $STATUS_ONLY; then
    [[ -f "$CRT_FILE" && -f "$KEY_FILE" ]] && success "Certs exist for $PROJECT" && exit 0 || { error "No certs"; exit 1; }
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

success "Certificates generated for $PROJECT ($HOST_DOMAIN)."