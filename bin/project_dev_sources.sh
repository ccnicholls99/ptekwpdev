#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — Dev Sources Management Script
#  Script: project_dev_sources.sh
#
#  Synopsis:
#    Add plugin/theme dev sources to CONFIG_BASE/config/projects.json.
#    Supports hybrid input (flags override, missing prompts).
#
#  Notes:
#    - Pure metadata modification (no provisioning)
#    - WHAT-IF safe
#    - Supports local + remote git sources
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail

# ------------------------------------------------------------------------------
# Preserve caller directory
# ------------------------------------------------------------------------------

CALLER_PWD="$(pwd)"
cleanup() { cd "$CALLER_PWD" || true; }
trap cleanup EXIT

# ------------------------------------------------------------------------------
# Resolve APP_BASE and load libraries
# ------------------------------------------------------------------------------

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "${APP_BASE}/lib/output.sh"
source "${APP_BASE}/lib/helpers.sh"
source "${APP_BASE}/lib/app_config.sh"

set_log --truncate "$(appcfg app_log_dir)/project_dev_sources.log" \
  "=== Dev Sources Run ($(date)) ==="

# ------------------------------------------------------------------------------
# Resolve CONFIG_BASE
# ------------------------------------------------------------------------------

CONFIG_BASE="$(appcfg config_base)"
PROJECTS_FILE="${CONFIG_BASE}/config/projects.json"

if [[ ! -f "$PROJECTS_FILE" ]]; then
  error "Missing projects.json at ${PROJECTS_FILE}"
  exit 1
fi

# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------

PROJECT=""
WHAT_IF=false
INTERACTIVE=false

DEV_PLUGINS=()
DEV_THEMES=()

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: project_dev_sources.sh --project <key> [options]

Options:
  --add-plugin name=... source=... type=local|remote init_git=true|false
  --add-theme  name=... source=... type=local|remote init_git=true|false

  --interactive              Prompt for missing dev sources
  -w, --what-if              Dry run (no changes applied)
  -h, --help                 Show this help

Notes:
  - This script ONLY modifies dev_sources in projects.json.
  - It does NOT scaffold directories or clone repos.
EOF
}

# ------------------------------------------------------------------------------
# Parse dev_source flags
# ------------------------------------------------------------------------------

parse_dev_source() {
  local entry="$1"
  local -n target_array="$2"

  local name="" source="" type="" init_git="false"

  IFS=',' read -ra parts <<< "$entry"
  for part in "${parts[@]}"; do
    key="${part%%=*}"
    val="${part#*=}"
    case "$key" in
      name) name="$val" ;;
      source) source="$val" ;;
      type) type="$val" ;;
      init_git) init_git="$val" ;;
    esac
  done

  if [[ -z "$name" || -z "$source" || -z "$type" ]]; then
    error "Invalid dev_source entry: $entry"
    exit 1
  fi

  target_array+=("{\"name\":\"$name\",\"source\":\"$source\",\"type\":\"$type\",\"init_git\":$init_git}")
}

# ------------------------------------------------------------------------------
# Parse flags
# ------------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --add-plugin) parse_dev_source "$2" DEV_PLUGINS; shift 2 ;;
    --add-theme) parse_dev_source "$2" DEV_THEMES; shift 2 ;;
    --interactive) INTERACTIVE=true; shift ;;
    -w|--what-if) WHAT_IF=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$PROJECT" ]]; then
  error "Missing required --project <key>"
  usage
  exit 1
fi

# ------------------------------------------------------------------------------
# Validate project exists
# ------------------------------------------------------------------------------

if ! jq -e ".projects.\"${PROJECT}\"" "$PROJECTS_FILE" >/dev/null; then
  error "Project '${PROJECT}' not found in projects.json"
  exit 1
fi

# ------------------------------------------------------------------------------
# Interactive dev_sources if requested
# ------------------------------------------------------------------------------

prompt_dev_sources() {
  local type="$1"
  local -n arr="$2"

  while true; do
    read -rp "Add a $type dev source? (y/n): " yn
    case "$yn" in
      y|Y)
        read -rp "  Name: " name
        read -rp "  Source path or git URL: " source
        read -rp "  Type (local/remote): " dtype
        read -rp "  init_git (true/false): " init_git
        arr+=("{\"name\":\"$name\",\"source\":\"$source\",\"type\":\"$dtype\",\"init_git\":$init_git}")
        ;;
      n|N) break ;;
      *) echo "Please enter y or n" ;;
    esac
  done
}

if $INTERACTIVE; then
  prompt_dev_sources "plugin" DEV_PLUGINS
  prompt_dev_sources "theme" DEV_THEMES
fi

# ------------------------------------------------------------------------------
# If no dev sources provided, nothing to do
# ------------------------------------------------------------------------------

if [[ ${#DEV_PLUGINS[@]} -eq 0 && ${#DEV_THEMES[@]} -eq 0 ]]; then
  info "No dev sources provided — nothing to update"
  exit 0
fi

# ------------------------------------------------------------------------------
# Build JSON fragments
# ------------------------------------------------------------------------------

plugins_json=$(printf "%s\n" "${DEV_PLUGINS[@]}" | jq -s '.')
themes_json=$(printf "%s\n" "${DEV_THEMES[@]}" | jq -s '.')

# ------------------------------------------------------------------------------
# Insert dev sources into projects.json
# ------------------------------------------------------------------------------

info "Updating dev_sources for project '${PROJECT}'"

if $WHAT_IF; then
  whatif "Would update dev_sources in ${PROJECTS_FILE}"
  echo "Plugins: $plugins_json"
  echo "Themes: $themes_json"
  exit 0
fi

tmpfile=$(mktemp)

jq \
  --argjson plugins "$plugins_json" \
  --argjson themes "$themes_json" \
  ".projects.\"${PROJECT}\".dev_sources.plugins += \$plugins |
   .projects.\"${PROJECT}\".dev_sources.themes += \$themes" \
  "$PROJECTS_FILE" > "$tmpfile"

mv "$tmpfile" "$PROJECTS_FILE"

success "dev_sources updated for project '${PROJECT}'"
exit 0