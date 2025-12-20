#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------
# cleanup-all.sh
# Full teardown for PtekWPDev
# ---------------------------------------------------------
# Removes:
#   - ALL project assets (via cleanup-project.sh --all)
#   - App-wide Docker
#   - CONFIG_BASE
#
# Supports:
#   --no-prompt
#   --what-if
#   --help
# ---------------------------------------------------------

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGFILE="$APP_BASE/logs/cleanup-all.log"

source "$APP_BASE/lib/output.sh" "$@"
source "$APP_BASE/lib/helpers.sh"

log_header "Full Cleanup"

# --- WHAT-IF flag ---
for arg in "$@"; do
    parse_what_if "$arg" || true
done

if [[ "$WHAT_IF" == true ]]; then
    whatif "Running in WHAT-IF mode — no destructive actions will be executed"
fi

# --- Help ---
show_help() {
    echo ""
    info "PtekWPDev Full Cleanup Utility"
    info "----------------------------------------"
    echo ""
    info "Usage:"
    info "  cleanup-all.sh"
    echo ""
    info "Options:"
    info "  -n, --no-prompt        Auto-confirm destructive actions"
    info "  -w, --what-if          Preview actions without executing them"
    info "  -h, --help             Show this help message and exit"
    echo ""
}

# --- Parse args ---
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

# --- Confirmation ---
if [[ "$NO_PROMPT" == false ]]; then
    confirm "This will DELETE ALL deployed assets. Continue" || {
        warn "Aborted by user."
        exit 0
    }
else
    info "Auto-confirm enabled (--no-prompt). Proceeding without interactive confirmation."
fi

# --- Step 1: Cleanup all projects ---
info "Cleaning ALL projects..."

run_or_preview "cleanup all projects" \
    "$APP_BASE/bin/cleanup-project.sh" --all --no-prompt ${WHAT_IF:+--what-if}

echo ""

# --- Step 2: App-wide Docker ---
APP_DOCKER="$APP_BASE/config/docker/compose.setup.yml"

if [[ -f "$APP_DOCKER" ]]; then
    info "Stopping app-wide Docker..."
    run_or_preview "docker compose down for app-wide setup" \
        docker compose -f "$APP_DOCKER" down --remove-orphans

    info "Pruning Docker volumes..."
    run_or_preview "docker volume prune" \
        docker volume prune -f
else
    warn "No app-wide docker compose file found."
fi

echo ""

# --- Step 3: Remove CONFIG_BASE ---
CONFIG_BASE="$HOME/.ptekwpdev"

info "Removing CONFIG_BASE: $CONFIG_BASE"
run_or_preview "remove CONFIG_BASE" \
    rm -rf "$CONFIG_BASE"

echo ""

success "Full cleanup complete."