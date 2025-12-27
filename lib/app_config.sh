#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — App Configuration Loader
#  Script: app_config.sh
#  Location: APP_BASE/lib/app_config.sh
#
#  Description:
#    Canonical loader for app-level configuration. Must be sourced, not executed.
#    Loads APP_BASE/app/config/ptekwpdev.json and stores all configuration
#    values in an in-memory associative array named PTEKWPCFG.
#
#  Contract:
#    - Must be sourced
#    - Never modifies caller's working directory
#    - Never exports environment variables
#    - Never leaks config outside the current shell
#    - Fails loudly if bootstrap has not been run
# ==============================================================================

# ------------------------------------------------------------------------------
# Prevent execution
# ------------------------------------------------------------------------------

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "ERROR: app_config.sh must be sourced, not executed."
  exit 1
fi

# ------------------------------------------------------------------------------
# Preserve caller directory
# ------------------------------------------------------------------------------

PTEK_CALLER_PWD="$(pwd)"
ptekwp_cleanup() {
  # PTEK_CALLER_PWD should always exist but let's keep shellcheck happy.
  cd "$PTEK_CALLER_PWD" || true
}
trap ptekwp_cleanup EXIT

# ------------------------------------------------------------------------------
# Resolve PTEK_APP_BASE (scripts always run from APP_BASE/bin)
# ------------------------------------------------------------------------------

PTEK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PTEK_APP_BASE="$(cd "${PTEK_LIB_DIR}/.." && pwd)"

PTEK_JSON_FILE="${PTEK_APP_BASE}/app/config/ptekwpdev.json"

# ------------------------------------------------------------------------------
# Ensure config exists
# ------------------------------------------------------------------------------

if [[ ! -f "$PTEK_JSON_FILE" ]]; then
  echo "ERROR: Missing app config file:"
  echo "  $PTEK_JSON_FILE"
  echo "Run: ${PTEK_APP_BASE}/bin/app_bootstrap.sh"
  # shellcheck disable=SC2317
  return 1 2>/dev/null || exit 1
fi

# ------------------------------------------------------------------------------
# Create global associative array for config
# ------------------------------------------------------------------------------

declare -g -A PTEKWPCFG

# ------------------------------------------------------------------------------
# Load JSON values into the dictionary
# ------------------------------------------------------------------------------

PTEKWPCFG[app_key]="$(jq -r '.APP_KEY' "$PTEK_JSON_FILE")"
PTEKWPCFG[app_base]="$(jq -r '.APP_BASE' "$PTEK_JSON_FILE")"
PTEKWPCFG[config_base]="$(jq -r '.CONFIG_BASE' "$PTEK_JSON_FILE")"
PTEKWPCFG[project_base]="$(jq -r '.PROJECT_BASE' "$PTEK_JSON_FILE")"

# Assets section
PTEKWPCFG[assets_container]="$(jq -r '.assets.container' "$PTEK_JSON_FILE")"
PTEKWPCFG[assets_root]="$(jq -r '.assets.root_path' "$PTEK_JSON_FILE")"

# ------------------------------------------------------------------------------
# Validate JSON values
# ------------------------------------------------------------------------------

if [[ "${PTEKWPCFG[app_base]}" != "$PTEK_APP_BASE" ]]; then
  echo "ERROR: PTEK_APP_BASE mismatch."
  echo "  From filesystem: $PTEK_APP_BASE"
  echo "  From JSON:       ${PTEKWPCFG[app_base]}"
  echo "This repo may have been moved. Re-run:"
  echo "  ${PTEK_APP_BASE}/bin/app_bootstrap.sh --no-prompt --overwrite"
  # shellcheck disable=SC2317
  return 1 2>/dev/null || exit 1
fi

required_keys=(
  app_key
  app_base
  config_base
  project_base
  assets_container
  assets_root
)

for key in "${required_keys[@]}"; do
  if [[ -z "${PTEKWPCFG[$key]:-}" ]]; then
    echo "ERROR: Required config value '$key' missing in ptekwpdev.json"
  # shellcheck disable=SC2317
    return 1 2>/dev/null || exit 1
  fi
done

# ------------------------------------------------------------------------------
# Derive static repo paths (not stored in JSON)
# ------------------------------------------------------------------------------

PTEKWPCFG[app_config_dir]="${PTEK_APP_BASE}/app/config"
PTEKWPCFG[app_log_dir]="${PTEK_APP_BASE}/app/logs"
PTEKWPCFG[app_bin_dir]="${PTEK_APP_BASE}/bin"
PTEKWPCFG[app_assets_dir]="${PTEK_APP_BASE}/app/assets"

# Runtime environments file
PTEKWPCFG[environments_file]="${PTEKWPCFG[config_base]}/environments.json"

# ------------------------------------------------------------------------------
# Load logging utilities (does NOT initialize logging)
# ------------------------------------------------------------------------------

PTEK_OUTPUT_LIB="${PTEK_APP_BASE}/lib/output.sh"

if [[ ! -f "$PTEK_OUTPUT_LIB" ]]; then
  echo "ERROR: Missing logging library:"
  echo "  $PTEK_OUTPUT_LIB"
  # shellcheck disable=SC2317
  return 1 2>/dev/null || exit 1
fi

# ------------------------------------------------------------------------------
# Helper: appcfg <key>
# Returns a config value from the PTEKWPCFG dictionary.
# ------------------------------------------------------------------------------
appcfg() {
  local key="$1"
  if [[ -z "${PTEKWPCFG[$key]+_}" ]]; then
    error "Config key not found: $key"
    return 1
  fi
  printf '%s\n' "${PTEKWPCFG[$key]}"
}

# shellcheck source=/dev/null
source "$PTEK_OUTPUT_LIB"