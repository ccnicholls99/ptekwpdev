#!/usr/bin/env bash
# ====App Config>>=============================================================
#  PTEKWPDEV — App Configuration Loader
#  Script: app_config.sh
#  Location: APP_BASE/lib/app_config.sh
#
#  Description:
#    Canonical loader for app-level configuration. Must be sourced, not executed.
#    Loads APP_BASE/app/config/app.json and flattens all keys into an in-memory
#    associative array (PTEKWPCFG) using dot-notation.
#
#  Contract:
#    - Must be sourced
#    - Never modifies caller's working directory
#    - Never exports environment variables
#    - Never leaks config outside the current shell
#    - Fails loudly if bootstrap has not been run
# ====<<App Config=============================================================

# -----------------------------------------------------------------------------
# Prevent execution
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "ERROR: app_config.sh must be sourced, not executed."
  exit 1
fi

# -----------------------------------------------------------------------------
# Preserve caller directory
# -----------------------------------------------------------------------------
PTEK_CALLER_PWD="$(pwd)"
ptekwp_cleanup() { cd "$PTEK_CALLER_PWD" || true; }
trap ptekwp_cleanup EXIT

# -----------------------------------------------------------------------------
# Resolve APP_BASE
# -----------------------------------------------------------------------------
PTEK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PTEK_APP_BASE="$(cd "${PTEK_LIB_DIR}/.." && pwd)"

# Prevent double-sourcing
[[ -n "${PTEK_LIB_APP_CONFIG_LOADED:-}" ]] && return
PTEK_LIB_APP_CONFIG_LOADED=1

# -----------------------------------------------------------------------------
# Load output/logging utilities early (defines error/info/success/etc.)
# -----------------------------------------------------------------------------
if [[ -z "${PTEK_LIB_OUTPUT_LOADED:-}" ]]; then
  # shellcheck source=/dev/null
  source "${PTEK_APP_BASE}/lib/output.sh"
fi

# -----------------------------------------------------------------------------
# Locate app.json (always inside the repo)
# -----------------------------------------------------------------------------
APP_JSON="${PTEK_APP_BASE}/app/config/app.json"

if [[ ! -f "$APP_JSON" ]]; then
  error "Missing app.json:"
  error "  $APP_JSON"
  error "Run: ${PTEK_APP_BASE}/bin/app_bootstrap.sh"
  return 1 2>/dev/null || exit 1
fi

# -----------------------------------------------------------------------------
# Create global associative array
# -----------------------------------------------------------------------------
declare -g -A PTEKWPCFG=()

# -----------------------------------------------------------------------------
# Flatten JSON into dot-notation keys
# -----------------------------------------------------------------------------
while IFS=$'\t' read -r key value; do
  clean_key="${key#.}"        # remove leading dot
  clean_val="${value%\"}"     # strip trailing quote
  clean_val="${clean_val#\"}" # strip leading quote
  PTEKWPCFG["$clean_key"]="$clean_val"
done < <(
  jq -r '
    paths(scalars) as $p |
    [ $p | join(".") ] + [ getpath($p) ] |
    @tsv
  ' "$APP_JSON"
)

# -----------------------------------------------------------------------------
# Accessor: appcfg <key>
# -----------------------------------------------------------------------------
appcfg() {
  local key="$1"
  if [[ -z "${PTEKWPCFG[$key]+_}" ]]; then
    error "Config key not found: $key"
    return 1
  fi
  printf '%s\n' "${PTEKWPCFG[$key]}"
}

# Optional debug helper
appcfg_dump() {
  for k in "${!PTEKWPCFG[@]}"; do
    printf '%s = %s\n' "$k" "${PTEKWPCFG[$k]}"
  done | sort
}

# -----------------------------------------------------------------------------
# Validate required keys
# -----------------------------------------------------------------------------
required_keys=(
  app_base
  config_base
  project_base
  backend_network
)

for key in "${required_keys[@]}"; do
  if [[ -z "${PTEKWPCFG[$key]:-}" ]]; then
    error "Required config key missing: $key"
    return 1 2>/dev/null || exit 1
  fi
done

# -----------------------------------------------------------------------------
# Validate APP_BASE consistency
# -----------------------------------------------------------------------------
if [[ "${PTEKWPCFG[app_base]}" != "$PTEK_APP_BASE" ]]; then
  error "APP_BASE mismatch."
  error "  Filesystem: $PTEK_APP_BASE"
  error "  app.json:   ${PTEKWPCFG[app_base]}"
  error "This repo may have been moved. Re-run:"
  error "  ${PTEK_APP_BASE}/bin/app_bootstrap.sh --force"
  return 1 2>/dev/null || exit 1
fi

# -----------------------------------------------------------------------------
# Derive static repo paths (not stored in JSON)
# -----------------------------------------------------------------------------
PTEKWPCFG[app_config_dir]="${PTEK_APP_BASE}/app/config"
PTEKWPCFG[app_log_dir]="${PTEK_APP_BASE}/app/logs"
PTEKWPCFG[app_bin_dir]="${PTEK_APP_BASE}/bin"
PTEKWPCFG[app_assets_dir]="${PTEK_APP_BASE}/app/assets"

# Canonical runtime project registry
PTEKWPCFG[projects_file]="${PTEKWPCFG[config_base]}/config/projects.json"

# -----------------------------------------------------------------------------
# Load logging utilities (does NOT initialize logging)
# -----------------------------------------------------------------------------
PTEK_OUTPUT_LIB="${PTEK_APP_BASE}/lib/output.sh"

if [[ ! -f "$PTEK_OUTPUT_LIB" ]]; then
  error "Missing logging library:"
  error "  $PTEK_OUTPUT_LIB"
  return 1 2>/dev/null || exit 1
fi

# shellcheck source=/dev/null
source "$PTEK_OUTPUT_LIB"