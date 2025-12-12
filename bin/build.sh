#!/usr/bin/env bash
#
# Build the WP Development Environment using Docker (ptekwpdev)

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
NO_PROMPT=false
AUTO_INSTALL=0
INIT_ENV=0
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
# Project resolution
# -------------------------------
PROJECTS_FILE="$CONFIG_BASE/$PROJECT_CONFIG_FILE"

if [[ -f "$PROJECTS_FILE" ]]; then
    if ! command -v jq >/dev/null 2>&1; then
        error "jq is required to read $PROJECTS_FILE"
        exit 4
    fi
    PROJECT_CONFIG=$(jq -r --arg pr "$PROJECT" '.environments[$pr]' "$PROJECTS_FILE")
    HOST_DOMAIN=$(echo "$PROJECT_CONFIG" | jq -r '.domain // empty')
    PROJECT_BASE=$(echo "$PROJECT_CONFIG" | jq -r '.baseDir // empty')

    if [[ -z "$PROJECT_BASE" || -z "$HOST_DOMAIN" ]]; then
        error "Project '$PROJECT' missing baseDir or domain in $PROJECTS_FILE"
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