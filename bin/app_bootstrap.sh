#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — App Bootstrap Script
#  Script: app_bootstrap.sh
#  Synopsis:
#    Initialize the application by generating app.json from defaults and
#    optional overrides in app.config.
#
#  Description:
#    - APP_BASE/app/config/app.json is the canonical static configuration.
#    - APP_BASE/app/config/app.config contains flat key=value overrides.
#    - This script merges app.config into app.json, expanding env vars.
#    - app.json is only overwritten with --force.
#
#  Notes:
#    - Must be executed from anywhere; APP_BASE is resolved automatically.
#    - Uses Option C logging.
#    - Never exports environment variables.
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail

# ------------------------------------------------------------------------------
# Resolve APP_BASE before anything else
# ------------------------------------------------------------------------------

PTEK_APP_BASE="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"
export PTEK_APP_BASE

# ------------------------------------------------------------------------------
# Load logging + config helpers
# ------------------------------------------------------------------------------

# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/app_config.sh"

APP_CONFIG_FILE="${PTEK_APP_BASE}/app/config/app.config"
APP_JSON_FILE="${PTEK_APP_BASE}/app/config/app.json"

set_log --truncate "$(appcfg app_log_dir)/app_bootstrap.log" \
  "=== App Bootstrap Run ($(date)) ==="

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: $(basename "$0") [--force]

Options:
  --force     Overwrite existing app.json

Description:
  Generates app.json by merging defaults with overrides from app.config.
EOF
}

FORCE=0
if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
fi

# ------------------------------------------------------------------------------
# Ensure app.config exists (generate from app.json if missing)
# ------------------------------------------------------------------------------

generate_app_config_from_json() {
  info "Generating default app.config from app.json"

  jq -r '
    def flatten($prefix):
      to_entries
      | map(
          if .value | type == "object" then
            (.value | flatten($prefix + .key + "."))[]
          else
            { key: ($prefix + .key), value: .value }
          end
        );
    flatten("") | .key + "=" + (.value|tostring)
  ' "$APP_JSON_FILE" > "$APP_CONFIG_FILE"

  success "Generated app.config from app.json"
}

if [[ ! -f "$APP_CONFIG_FILE" ]]; then
  generate_app_config_from_json
fi

# ------------------------------------------------------------------------------
# Merge app.config overrides into JSON
# ------------------------------------------------------------------------------

merge_overrides() {
  local jq_cmd="."

  while IFS= read -r line; do
    # Trim whitespace
    line="${line#"${line%%[![:space:]]*}"}"

    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Skip comments
    [[ "${line:0:1}" == "#" ]] && continue

    # Split key=value
    key="${line%%=*}"
    value="${line#*=}"

    # Expand env vars: $HOME, ~, $APP_KEY, etc.
    expanded_value="$(eval echo "$value")"

    info "Applying override: ${key}=${expanded_value}"

    # Append to jq command
    jq_cmd+=" | .${key} = \"${expanded_value}\""
  done < "$APP_CONFIG_FILE"

  # Apply jq merge
  jq "$jq_cmd" "$APP_JSON_FILE"
}

# ------------------------------------------------------------------------------
# Main Logic
# ------------------------------------------------------------------------------

if [[ -f "$APP_JSON_FILE" && "$FORCE" -ne 1 ]]; then
  error "app.json already exists. Use --force to overwrite from app.config."
  exit 1
fi

info "Merging app.config overrides into app.json"

merge_overrides > "${APP_JSON_FILE}.tmp"
mv "${APP_JSON_FILE}.tmp" "$APP_JSON_FILE"

success "app.json generated successfully at: $APP_JSON_FILE"