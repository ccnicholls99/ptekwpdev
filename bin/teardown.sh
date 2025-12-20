#!/usr/bin/env bash
set -euo pipefail



# ---------------------------------------------------------
# Cleanup Script for PtekWPDev
# ---------------------------------------------------------
# Modes:
#   HARD CLEANUP (default):
#       cleanup.sh <project>
#       - Removes project Docker + directory
#       - Removes app-wide Docker
#       - Removes CONFIG_BASE
#
#   PROJECT-ONLY CLEANUP:
#       cleanup.sh --project-only <project1> [project2 ...]
#       - Removes project Docker + directory
#       - Leaves CONFIG_BASE intact
#       - Leaves app-wide Docker intact
#
# WHAT-IF mode:
#       cleanup.sh --what-if ...
#
# Non-interactive mode:
#       cleanup.sh --no-prompt ...
#
# Help:
#       cleanup.sh --help
# ---------------------------------------------------------

# --- 1. Resolve APP_BASE ---------------------------------
APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- 2. Configure logging BEFORE sourcing output.sh -------
LOGFILE="$APP_BASE/logs/cleanup.log"

# --- 3. Source logging + helper utilities -----------------
source "$APP_BASE/lib/output.sh" "$@"
source "$APP_BASE/lib/helpers.sh"

echo "+------------------------------------------------------------------"
error "teardown.sh is obsolete. Use cleanup-all.sh or cleanup-project.sh"
echo "+------------------------------------------------------------------"
exit 1

log_header "Cleanup"

# --- 4. Parse WHAT-IF flag early --------------------------
for arg in "$@"; do
    parse_what_if "$arg" || true
done

if [[ "$WHAT_IF" == true ]]; then
    whatif "Running in WHAT-IF mode — no destructive actions will be executed"
fi

# --- 5. Guard: script must not run without intent ---------
if [[ $# -eq 0 ]]; then
    error "No arguments provided. Cleanup requires an explicit intent."
    error "Run 'cleanup.sh --help' for usage."
    exit 1
fi

# --- 6. Help function -------------------------------------
show_help() {
    echo ""
    info "PtekWPDev Cleanup Utility"
    info "----------------------------------------"
    info "!!! Use with caution. Be sure to backup any assets you wish to preserve. !!!"
    echo ""
    info "Usage:"
    info "  cleanup.sh <project>"
    info "      Hard cleanup: removes project, app-wide Docker, and CONFIG_BASE"
    echo ""
    info "  cleanup.sh --project-only <project1> [project2 ...]"
    info "      Project-only cleanup: removes project(s) only"
    echo ""
    info "Options:"
    info "  -p, --project-only     Cleanup only the specified project(s)"
    info "  -n, --no-prompt        Auto-confirm destructive actions"
    info "  -w, --what-if          Preview actions without executing them"
    info "  -h, --help             Show this help message and exit"
    echo ""
    info "Examples:"
    info "  cleanup.sh myproject"
    info "  cleanup.sh --no-prompt myproject"
    info "  cleanup.sh --project-only site1 site2"
    info "  cleanup.sh --what-if --project-only site1"
    echo ""
}

# --- 7. Parse CLI args ------------------------------------
PROJECT_ONLY=false
NO_PROMPT=false
PROJECTS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -p|--project-only)
            PROJECT_ONLY=true
            shift
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
            PROJECTS+=("$1")
            shift
            ;;
    esac
done

if [[ ${#PROJECTS[@]} -eq 0 ]]; then
    error "No project(s) specified."
    error "Run 'cleanup.sh --help' for usage."
    exit 1
fi

# --- 8. Check required binaries ---------------------------
check_binary docker jq

# --- 9. Define CONFIG_BASE --------------------------------
CONFIG_BASE="$HOME/.ptekwpdev"
ENV_FILE="$CONFIG_BASE/environments.json"

if [[ ! -f "$ENV_FILE" ]]; then
    error "environments.json not found at: $ENV_FILE"
    error "Cannot determine PROJECT_BASE. Aborting."
    exit 1
fi

# --- 10. Resolve PROJECT_BASE from generated config --------
PROJECT_BASE="$(jq -r '.app.project_base' "$ENV_FILE")"

if [[ -z "$PROJECT_BASE" || "$PROJECT_BASE" == "null" ]]; then
    error "project_base not defined in $ENV_FILE"
    exit 1
fi

# --- 11. Confirmation logic -------------------------------
if [[ "$NO_PROMPT" == false ]]; then
    confirm "This will DELETE ALL deployed assets. Make sure you have backed up any key files and assets!  Do you want to Continue" || {
        warn "Aborted by user."
        exit 0
    }
else
    info "Auto-confirm enabled (--no-prompt). Proceeding without interactive confirmation."
fi

# --- 12. Project cleanup function --------------------------
cleanup_project() {
    local project="$1"
    local project_path="$PROJECT_BASE/$project"
    local project_docker="$project_path/docker/compose.project.yml"

    info "----- Cleaning project: $project -----"

    # Tear down project Docker
    if [[ -f "$project_docker" ]]; then
        info "Stopping and removing Docker containers for $project..."
        run_or_preview "docker compose down for $project" \
            docker compose -f "$project_docker" down --remove-orphans

        info "Removing Docker volumes..."
        run_or_preview "docker volume prune" \
            docker volume prune -f
    else
        warn "No docker compose file found for $project. Skipping Docker cleanup."
    fi

    # Remove project directory
    if [[ -d "$project_path" ]]; then
        info "Removing project directory: $project_path"
        run_or_preview "remove project directory" \
            rm -rf "$project_path"
    else
        warn "Project directory not found: $project_path"
    fi

    newline
}

# --- 13. PROJECT-ONLY MODE --------------------------------
if [[ "$PROJECT_ONLY" == true ]]; then
    info "Running in PROJECT-ONLY cleanup mode"
    newline

    for project in "${PROJECTS[@]}"; do
        cleanup_project "$project"
    done

    success "Project-only cleanup complete."
    exit 0
fi

# --- 14. HARD CLEANUP MODE --------------------------------
info "Running HARD cleanup mode"
newline

# Only one project allowed in hard mode
if [[ ${#PROJECTS[@]} -ne 1 ]]; then
    error "Hard cleanup requires exactly one project."
    exit 1
fi

PROJECT_NAME="${PROJECTS[0]}"

cleanup_project "$PROJECT_NAME"

# --- 15. Tear down app-wide Docker -------------------------
APP_DOCKER="$APP_BASE/config/docker/compose.setup.yml"

if [[ -f "$APP_DOCKER" ]]; then
    info "Stopping and removing app-wide Docker containers..."
    run_or_preview "docker compose down for app-wide setup" \
        docker compose -f "$APP_DOCKER" down --remove-orphans

    info "Removing Docker volumes..."
    run_or_preview "docker volume prune" \
        docker volume prune -f
else
    warn "No app-wide docker compose file found. Skipping app-wide Docker cleanup."
fi

# --- 16. Remove CONFIG_BASE -------------------------------
info "Removing CONFIG_BASE: $CONFIG_BASE"
run_or_preview "remove CONFIG_BASE" \
    rm -rf "$CONFIG_BASE"

success "HARD cleanup complete. All deployed assets removed."