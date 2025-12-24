#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------
# cleanup-all.sh
# Full cleanup of all deployed environments + app assets
# ---------------------------------------------------------
# Performs:
#   - Loop over all environments in environments.json
#   - Calls cleanup-project.sh -p <project>
#   - Tears down app-wide Docker assets
#   - Removes CONFIG_BASE
#
# Supports:
#   -n, --no-prompt
#   -w, --what-if
#   -h, --help
# ---------------------------------------------------------

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Ensure log directory exists
mkdir -p "$APP_BASE/logs"
LOGFILE="$APP_BASE/logs/cleanup-all.log"

source "$APP_BASE/lib/output.sh"
source "$APP_BASE/lib/helpers.sh"

log_header "Full Cleanup"

#echo "Script Args=$@"

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
    printf "%s\n" "PtekWPDev Full Cleanup Utility"
    printf "%s\n" "----------------------------------------"
    printf "%s\n" ""
    printf "%s\n" "Usage:"
    printf "%s\n" "  cleanup-all.sh [options]"
    printf "%s\n" ""
    printf "%s\n" "Options:"
    printf "%s\n" "  -n, --no-prompt        Auto-confirm destructive actions"
    printf "%s\n" "  -w, --what-if          Preview actions without executing"
    printf "%s\n" "  -h, --help             Show this help message and exit"
    printf "%s\n" ""
}

# Default to help if no args
#if (( $# == 0 )); then
#    show_help
#    exit 0
#fi

# ---------------------------------------------------------
# Parse args
# ---------------------------------------------------------
NO_PROMPT=false

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
# Load environments.json
# ---------------------------------------------------------
CONFIG_BASE="${CONFIG_BASE:-$HOME/.ptekwpdev}"
ENV_FILE="$CONFIG_BASE/environments.json"

# Always declare ENV_LIST as an array to avoid unbound variable errors
declare -a ENV_LIST=()

if [[ ! -f "$ENV_FILE" ]]; then
    warn "No environments.json found at $ENV_FILE — nothing to clean."
    success "Cleanup complete — no environments detected."
    exit 0
fi

# environments.json exists — load environments
mapfile -t ENV_LIST < <(jq -r '.environments | keys[]?' "$ENV_FILE")

# ---------------------------------------------------------
# Preflight Check
# ---------------------------------------------------------
info "Preflight Check — reviewing assets scheduled for removal..."

# Read project_base from the app section
PROJECT_BASE="$(jq -r '.app.project_base // empty' "$ENV_FILE")"

if [[ -z "$PROJECT_BASE" ]]; then
    error "Missing .app.project_base in $ENV_FILE — cannot resolve project directories."
    exit 1
fi

if (( ${#ENV_LIST[@]} > 0 )); then
    info "Projects to be removed:"
    for env in "${ENV_LIST[@]}"; do
        BASE_DIR="$(jq -r ".environments[\"$env\"].base_dir // empty" "$ENV_FILE")"

        if [[ -z "$BASE_DIR" ]]; then
            warn "Project '$env' has no base_dir defined — skipping."
            continue
        fi

        PROJECT_DIR="${PROJECT_BASE%/}/${BASE_DIR#/}"
        echo "  - $env  (dir: $PROJECT_DIR)"
    done
else
    warn "No deployed environments found — no project directories will be removed."
fi

echo ""
info "App-wide Docker assets:"
echo "  - $APP_BASE/config/docker/compose.app.yml"

echo ""
info "Configuration directory to be removed:"
echo "  - $CONFIG_BASE"
echo ""

# ---------------------------------------------------------
# Confirmation
# ---------------------------------------------------------
if [[ "$NO_PROMPT" == false ]]; then

    warn "WARNING: This command will remove all deployed projects and app assets.\nMake sure you have backed up any key assets to a location outside the ptekwpdev filesystem.\n\nIf you wish to remove a single project, use $APP_BASE/bin/cleanup-project.sh instead.\n\n"
    confirm "Do you wish to proceed?" || {
        warn "Aborted by user."
        exit 0
    }
else
    info "Auto-confirm enabled (--no-prompt). Proceeding without interactive confirmation."
fi

# ---------------------------------------------------------
# Step 1: Cleanup all projects
# ---------------------------------------------------------
# ---------------------------------------------------------
# Step 1: Cleanup all projects
# ---------------------------------------------------------
if (( ${#ENV_LIST[@]} > 0 )); then
    info "Cleaning all deployed projects..."

    for env in "${ENV_LIST[@]}"; do
        info "Invoking cleanup-project.sh for: $env"

        if [[ "$WHAT_IF" == true ]]; then
            # WHAT‑IF mode → explicitly pass -w
            run_or_preview "cleanup project $env" \
                "$APP_BASE/bin/cleanup-project.sh" \
                -p "$env" \
                --no-prompt \
                --what-if
        else
            # Normal mode → do NOT pass -w
            run_or_preview "cleanup project $env" \
                "$APP_BASE/bin/cleanup-project.sh" \
                -p "$env" \
                --no-prompt
        fi
        echo "[DEBUG] Returned from cleanup-project.sh for: $env" >&2
    done
else
    warn "No deployed environments found — skipping project cleanup."
fi

echo "[DEBUG] Reached after project loop in cleanup-all.sh" >&2

# ---------------------------------------------------------
# Step 2: App-wide Docker teardown
# ---------------------------------------------------------
APP_DOCKER="$APP_BASE/config/docker/compose.app.yml"

if [[ -f "$APP_DOCKER" ]]; then
    info "Tearing down app-wide Docker assets..."

    run_or_preview "docker compose down for app" \
        docker compose -f "$APP_DOCKER" down --remove-orphans

    run_or_preview "docker volume prune" \
        docker volume prune -f
else
    warn "App compose file not found: $APP_DOCKER"
fi

# ---------------------------------------------------------
# Step 3: Remove CONFIG_BASE
# ---------------------------------------------------------
info "Removing CONFIG_BASE: $CONFIG_BASE"

run_or_preview "remove CONFIG_BASE" \
    rm -rf "$CONFIG_BASE"

echo ""
success "Full cleanup complete."