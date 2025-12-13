#!/usr/bin/env bash
#
# Build the WP Development Environment using Docker (ptekwpdev)
# - Centralized project lookup in ~/.ptekwpdev/environments.json
# - Requires each project to define domain and base_dir explicitly
# - Shared output functions sourced from APP_BASE/lib/output.sh
# - Automation-ready with --no-prompt
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
PROJECT_CONFIG_FILE="environments.json"
CONFIG_BASE="$HOME/.ptekwpdev"
NO_PROMPT=false
AUTO_INSTALL=0
INIT_ENV=0        # 0=No, 1=Confirm, 2=Yes
KEYGEN=0
CERT_TOOL="openssl"

# -------------------------------
# Load shared output functions
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
    echo "Usage: $(basename "$0") --project NAME [options] [-- docker-compose-args]"
    echo
    echo "Options:"
    echo "  -p, --project NAME        REQUIRED: Project name to look up in ~/.ptekwpdev/environments.json"
    echo "      --no-prompt           Disable interactive prompts; fail fast if config missing"
    echo "  -a, --auto-install        Run post-build autoinstall script if build succeeds"
    echo "  -i, --init                Re-initialize environment (purge volumes)"
    echo "  -o, --overwrite           Skip confirmation for --init (Just Do It)"
    echo "  -k, --keygen              Regenerate SSL certificates for the proxy"
    echo "  -c, --cert-tool TOOL      Certificate tool for keygen: 'openssl' (default) or 'mkcert'"
    echo "  -h, --help                Show this help message and exit"
    echo
    echo "Example:"
    echo "  $(basename "$0") --project demo --auto-install -- --build-arg CACHEBUST=$(date +%s)"
}

# -------------------------------
# Option parsing
# -------------------------------
ARGS=()
DC_ARGS=()
SEEN_DOUBLE_DASH=false

for arg in "$@"; do
    if $SEEN_DOUBLE_DASH; then
        DC_ARGS+=("$arg")
    else
        if [[ "$arg" == "--" ]]; then
            SEEN_DOUBLE_DASH=true
        else
            ARGS+=("$arg")
        fi
    fi
done

set -- "${ARGS[@]}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--project) PROJECT="$2"; shift 2 ;;
        --no-prompt) NO_PROMPT=true; shift ;;
        -a|--auto-install) AUTO_INSTALL=1; shift ;;
        -i|--init) INIT_ENV=1; shift ;;
        -o|--overwrite) [[ $INIT_ENV -eq 1 ]] && INIT_ENV=2; shift ;;
        -k|--keygen) KEYGEN=1; shift ;;
        -c|--cert-tool) CERT_TOOL="$2"; shift 2 ;;
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
PROJECTS_FILE="$CONFIG_BASE/$PROJECT_CONFIG_FILE"

if [[ -f "$PROJECTS_FILE" ]]; then
    if ! command -v jq >/dev/null 2>&1; then
        error "jq is required to read $PROJECTS_FILE"
        exit 4
    fi

    APP_PROJECT_BASE=$(jq -r '.app.project_base' "$PROJECTS_FILE" | sed "s|\$HOME|$HOME|")
    PROJECT_CONFIG=$(jq -r --arg pr "$PROJECT" '.environments[$pr]' "$PROJECTS_FILE")

    HOST_DOMAIN=$(echo "$PROJECT_CONFIG" | jq -r '.domain // empty')

    # Strip any leading slash from base_dir
    BASE_DIR_REL=$(echo "$PROJECT_CONFIG" | jq -r '.base_dir // empty' | sed 's|^/||')

    PROJECT_BASE="$APP_PROJECT_BASE/$BASE_DIR_REL"

    # After PROJECT_BASE is resolved
    # Normalize logging output to project log file
    LOG_DIR="$PROJECT_BASE/app/logs"
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/build.log"
    exec > >(tee -a "$LOG_FILE") 2>&1

warn "Starting build for $PROJECT at $(date)"

    if [[ -z "$BASE_DIR_REL" || -z "$HOST_DOMAIN" ]]; then
        error "Project '$PROJECT' missing base_dir or domain in $PROJECTS_FILE"
        exit 5
    fi
else
    error "No centralized $PROJECT_CONFIG_FILE found in $CONFIG_BASE"
    exit 3
fi

warn "$(printf "Env Check:\n\tProject: %s\n\tProjectBase: %s\n\tDomain: %s\n" \
    "$PROJECT" "$PROJECT_BASE" "$HOST_DOMAIN")"

# -------------------------------
# Validate project directory structure
# -------------------------------
for dir in app bin docker src; do
    [[ ! -e "$PROJECT_BASE/$dir" ]] && error "Missing required directory: $PROJECT_BASE/$dir" && exit 1
done

# -------------------------------
# Init execution (purge volumes)
# -------------------------------
if [[ $INIT_ENV -eq 2 ]]; then
    warn "Init activated. Removing old volumes."
    docker volume rm "${PROJECT}_wordpress" "${PROJECT}_sql-data" || true
fi

# -------------------------------
# Key generation (SSL)
# -------------------------------
if [[ $KEYGEN -eq 1 ]]; then
    warn "Regenerating SSL certificates for project: $PROJECT"
    CERT_SCRIPT="$PROJECT_BASE/bin/generate_certs.sh"
    if [[ -x "$CERT_SCRIPT" ]]; then
        bash "$CERT_SCRIPT" --project "$PROJECT" --cert-tool "$CERT_TOOL" --no-prompt
    else
        error "Certificate script not found or not executable: $CERT_SCRIPT"
        exit 1
    fi
fi

# -------------------------------
# Docker compose build/up
# -------------------------------
COMPOSE_FILE="$PROJECT_BASE/app/config/docker/compose.build.yml"
if [[ ! -f "$COMPOSE_FILE" ]]; then
    error "Compose file not found: $COMPOSE_FILE"
    exit 1
fi

warn "Running docker compose (build + up)..."
docker compose -f "$COMPOSE_FILE" up -d --build "${DC_ARGS[@]}"

# -------------------------------
# Post-build verification
# -------------------------------
WP_CONTAINER="${PROJECT}_wp"
warn "Verifying source mount in WordPress container..."
if ! docker exec "$WP_CONTAINER" ls -l /usr/src/ptekwpdev/src >/dev/null 2>&1; then
    error "Source code not mounted correctly at /usr/src/ptekwpdev/src"
    exit 1
fi

# -------------------------------
# Auto install (optional)
# -------------------------------
if [[ $AUTO_INSTALL -eq 1 ]]; then
    warn "Running Auto Install..."
    AUTO_SCRIPT="$PROJECT_BASE/bin/autoinstall.sh"
    if [[ -x "$AUTO_SCRIPT" ]]; then
        bash "$AUTO_SCRIPT" --project "$PROJECT"
    else
        error "Auto install script not found or not executable: $AUTO_SCRIPT"
        exit 1
    fi
fi

success "Build completed successfully and source verified."