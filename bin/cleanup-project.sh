#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------
# cleanup-project.sh
# Project-only cleanup for PtekWPDev
# ---------------------------------------------------------
# Removes:
#   - Project Docker containers, networks, volumes
#   - Project directory under PROJECT_BASE
#
# Does NOT remove:
#   - CONFIG_BASE
#   - App-wide Docker
#
# Supports:
#   --all
#   --no-prompt
#   --what-if
#   --help
# ---------------------------------------------------------

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGFILE="$APP_BASE/logs/cleanup-project.log"

source "$APP_BASE/lib/output.sh" "$@"
source "$APP_BASE/lib/helpers.sh"

log_header "Project Cleanup"

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
    info "PtekWPDev Project Cleanup Utility"
    info "----------------------------------------"
    echo ""
    info "Usage:"
    info "  cleanup-project.sh <project>"
    info "  cleanup-project.sh --all"
    echo ""
    info "Options:"
    info "  -a, --all              Cleanup ALL projects"
    info "  -n, --no-prompt        Auto-confirm destructive actions"
    info "  -w, --what-if          Preview actions without executing them"
    info "  -h, --help             Show this help message and exit"
    echo ""
}

# --- Guard: must have args ---
if [[ $# -eq 0 ]]; then
    error "No arguments provided. Run 'cleanup-project.sh --help' for usage."
    exit 1
fi

# --- Parse args ---
ALL_PROJECTS=false
NO_PROMPT=false
PROJECTS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -a|--all)
            ALL_PROJECTS=true
            shift
            ;;
        -n|--no-prompt)
            NO_PROMPT=true
            shift
            ;;
        -w|--what-if)
            shift
            ;;
        -*)
            warn "Unknown flag: $1"
            shift
            ;;
        *)
            PROJECTS+=("$1")
            shift
            ;;
    esac
done

check_binary docker jq

CONFIG_BASE="$HOME/.ptekwpdev"
ENV_FILE="$CONFIG_BASE/environments.json"

if [[ ! -f "$ENV_FILE" ]]; then
    error "environments.json not found at: $ENV_FILE"
    exit 1
fi

PROJECT_BASE="$(jq -r '.app.project_base' "$ENV_FILE")"

if [[ "$PROJECT_BASE" == "null" || -z "$PROJECT_BASE" ]]; then
    error "project_base not defined in environments.json"
    exit 1
fi

# --- Resolve ALL projects ---
if [[ "$ALL_PROJECTS" == true ]]; then
    if [[ -d "$PROJECT_BASE" ]]; then
        mapfile -t PROJECTS < <(find "$PROJECT_BASE" -mindepth 1 -maxdepth 1 -type d -printf "%f\n")
    else
        error "PROJECT_BASE directory not found: $PROJECT_BASE"
        exit 1
    fi
fi

if [[ ${#PROJECTS[@]} -eq 0 ]]; then
    error "No projects specified or found."
    exit 1
fi

# --- Confirmation ---
if [[ "$NO_PROMPT" == false ]]; then
    confirm "This will DELETE project assets. Continue" || {
        warn "Aborted by user."
        exit 0
    }
else
    info "Auto-confirm enabled (--no-prompt). Proceeding without interactive confirmation."
fi

# --- Cleanup function ---
cleanup_project() {
    local project="$1"
    local project_path="$PROJECT_BASE/$project"
    local project_docker="$project_path/docker/compose.project.yml"

    info "----- Cleaning project: $project -----"

    if [[ -f "$project_docker" ]]; then
        info "Stopping Docker for $project..."
        run_or_preview "docker compose down for $project" \
            docker compose -f "$project_docker" down --remove-orphans

        info "Pruning Docker volumes..."
        run_or_preview "docker volume prune" docker volume prune -f
    else
        warn "No docker compose file for $project"
    fi

    if [[ -d "$project_path" ]]; then
        info "Removing project directory: $project_path"
        run_or_preview "remove project directory" rm -rf "$project_path"
    else
        warn "Project directory not found: $project_path"
    fi

    echo ""
}

# --- Execute cleanup ---
for project in "${PROJECTS[@]}"; do
    cleanup_project "$project"
done

success "Project cleanup complete."