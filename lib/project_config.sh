#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — Project Configuration Loader
#  Script: project_config.sh
#  Location: APP_BASE/lib/project_config.sh
#
#  Description:
#    Canonical loader for project-level configuration. Must be sourced, not
#    executed. Loads CONFIG_BASE/config/projects.json and flattens all keys
#    for the selected project into an in-memory associative array (PTEKPRCFG)
#    using dot-notation.
#
#    This script provides a stable, contributor-safe interface for accessing
#    project configuration derived from the app-level template:
#      APP_BASE/app/config/projects.tpl.json
#
#  Contract:
#    - Must be sourced
#    - Never modifies caller's working directory
#    - Never exports environment variables
#    - Never leaks config outside the current shell
#    - Fails loudly if bootstrap has not been run
# ==============================================================================

# --------------------------------------------------------------------
# Safety: prevent direct execution
# --------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: project_config.sh must be sourced, not executed." >&2
  exit 1
fi

# --------------------------------------------------------------------
# Ensure app_config.sh is already loaded
# --------------------------------------------------------------------
if ! declare -p PTEKWPCFG >/dev/null 2>&1; then
  echo "ERROR: app_config.sh must be sourced before project_config.sh" >&2
  return 1
fi

# --------------------------------------------------------------------
# Globals
# --------------------------------------------------------------------
declare -gA PTEKPRCFG=()

# --------------------------------------------------------------------
# Helper: prcfg <key>
# --------------------------------------------------------------------
prcfg() {
  local key="$1"
  if [[ -z "$key" ]]; then
    echo "ERROR: prcfg requires a key" >&2
    return 1
  fi
  echo "${PTEKPRCFG[$key]}"
}

# --------------------------------------------------------------------
# Load project config
# Usage: project_config_load <project_key>
# --------------------------------------------------------------------
project_config_load() {
  local project_key="$1"

  if [[ -z "$project_key" ]]; then
    echo "ERROR: project_config_load requires a project key" >&2
    return 1
  fi

  local projects_file
  projects_file="$(appcfg config_base)/config/projects.json"

  if [[ ! -f "$projects_file" ]]; then
    echo "ERROR: projects.json not found at: $projects_file" >&2
    return 1
  fi

  # Extract project block
  local project_json
  project_json="$(jq -r --arg key "$project_key" '.projects[$key]' "$projects_file")"

  if [[ "$project_json" == "null" ]]; then
    echo "ERROR: Project '$project_key' not found in projects.json" >&2
    return 1
  fi

  # --------------------------------------------------------------------
  # Validate required top-level keys
  # --------------------------------------------------------------------
  local required_keys=(
    "project_domain"
    "project_network"
    "base_dir"
    "wordpress"
    "secrets"
    "dev_sources"
  )

  for key in "${required_keys[@]}"; do
    if ! jq -e --arg k "$key" '.[$k] != null' <<<"$project_json" >/dev/null; then
      echo "ERROR: Missing required key '$key' in project '$project_key'" >&2
      return 1
    fi
  done

  # --------------------------------------------------------------------
  # Flatten project JSON into PTEKPRCFG
  # --------------------------------------------------------------------
  while IFS="=" read -r k v; do
    PTEKPRCFG["$k"]="$v"
  done < <(
    jq -r '
      to_entries
      | .[]
      | if (.value | type) == "object" then
          .value
          | to_entries
          | .[]
          | "\(.key)=\(.value)"
        else
          "\(.key)=\(.value)"
        end
    ' <<<"$project_json"
  )

  # --------------------------------------------------------------------
  # Add derived values
  # --------------------------------------------------------------------
  PTEKPRCFG["project_key"]="$project_key"
  PTEKPRCFG["project_repo"]="$(appcfg project_base)/${PTEKPRCFG[base_dir]}"

  return 0
}

# End of file