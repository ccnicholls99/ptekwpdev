#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------
# cleanup-project.sh
# Cleanup for a single deployed environment
# ---------------------------------------------------------
# Removes:
#   - Project-specific Docker assets
#   - Project directory (from environments.json)
#
# Supports:
#   -p, --project <name>
#   -n, --no-prompt
#   -w, --what-if
#   -h, --help
# ---------------------------------------------------------

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGFILE="$APP_BASE/logs/cleanup-project.log"

source "$APP_BASE/lib/output.sh" "$@"
source "$APP_BASE/lib/helpers.sh"

log_header "Project Cleanup"

# debug only: echo "Script Args=$@"

# ---------------------------------------------------------
# WHAT-IF flag (pre-parse)
# ---------------------------------------------------------
for arg in "$@"; do
    parse_what_if "$arg" || true
done

if [[ "$WHAT_IF" == true ]]; then
    whatif "Running in WHAT-IF mode — no destructive actions will be executed"
fi

# ---------------------------------------------------------
# Help
# ---------------------------------------------------------
show_help() {
    printf "%s\n" ""
    printf "%s\n" "PtekWPDev Project Cleanup Utility"
    printf "%s\n" "----------------------------------------"
    printf "%s\n" ""
    printf "%s\n" "Usage:"
    printf "%s\n" "  cleanup-project.sh -p <project-name> [options]"
    printf "%s\n" ""
    printf "%s\n" "Options:"
    printf "%s\n" "  -p, --project <name>  Project key from environments.json"
    printf "%s\n" "  -n, --no-prompt       Auto-confirm destructive actions"
    printf "%s\n" "  -w, --what-if         Preview actions without executing"
    printf "%s\n" "  -h, --help            Show this help message and exit"
    printf "%s\n" ""
}

# Default to help if no args
if (( $# == 0 )); then
    show_help
    exit 0
fi

# ---------------------------------------------------------
# Parse args
# ---------------------------------------------------------
NO_PROMPT=false
PROJECT_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -n|--no-prompt)
            NO_PROMPT=true
            shift
            ;;
        -w|--what-if)
            # already handled by parse_what_if
            shift
            ;;
        -p|--project)
            if [[ -z "${2:-}" ]]; then
                error "--project requires a project name"
                exit 1
            fi
            PROJECT_NAME="$2"
            shift 2
            ;;
        -*)
            warn "Unknown flag: $1"
            shift
            ;;
        *)
            warn "Ignoring unexpected argument: $1"
            shift
            ;;
    esac
done

# ---------------------------------------------------------
# Validate project name
# ---------------------------------------------------------
if [[ -z "$PROJECT_NAME" ]]; then
    error "No project name provided. Use -p <name>."
    printf "\n"
    show_help
    exit 1
fi

# ---------------------------------------------------------
# Load environments.json
# ---------------------------------------------------------
CONFIG_BASE="${CONFIG_BASE:-$HOME/.ptekwpdev}"
ENV_FILE="$CONFIG_BASE/environments.json"

# ---------------------------------------------------------
# Resolve project directory
# ---------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
    error "environments.json not found at $ENV_FILE"
    exit 1
fi

# Read project_base from the app section
PROJECT_BASE="$(jq -r '.app.project_base // empty' "$ENV_FILE")"

if [[ -z "$PROJECT_BASE" ]]; then
    error "Missing .app.project_base in $ENV_FILE — cannot resolve project directory."
    exit 1
fi

# Read base_dir for this project
BASE_DIR="$(jq -r ".environments[\"$PROJECT\"].base_dir // empty" "$ENV_FILE")"

if [[ -z "$BASE_DIR" ]]; then
    error "Missing base_dir for project '$PROJECT' in $ENV_FILE"
    exit 1
fi

# Construct full project directory
PROJECT_DIR="${PROJECT_BASE}${BASE_DIR}"
info "Resolved project directory: $PROJECT_DIR"

# ---------------------------------------------------------
# Confirmation
# ---------------------------------------------------------
if [[ "$NO_PROMPT" == false ]]; then
    confirm "This will DELETE assets for project '$PROJECT_NAME'. Continue" || {
        warn "Aborted by user."
        exit 0
    }
else
    info "Auto-confirm enabled (--no-prompt). Proceeding without interactive confirmation."
fi

# ---------------------------------------------------------
# Cleanup logic
# ---------------------------------------------------------
info "Cleaning project: $PROJECT_NAME"

# Docker teardown
COMPOSE_FILE="$APP_BASE/config/docker/compose.project.yml"
if [[ -f "$COMPOSE_FILE" ]]; then
    run_or_preview "docker compose down for $PROJECT_NAME" \
        docker compose -f "$COMPOSE_FILE" \
        --project-name "$PROJECT_NAME" down --remove-orphans
else
    warn "Project compose file not found: $COMPOSE_FILE"
fi

# Remove project directory
if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
    run_or_preview "remove project directory $PROJECT_DIR" \
        rm -rf "$PROJECT_DIR"
else
    warn "Project directory not found or empty: $PROJECT_DIR"
fi

echo ""
success "Project cleanup complete."