#!/usr/bin/env bash
# ====Summary>>=================================================================
# PTEKWPDEV — a multi-project, bootstrap app for localized WordPress development
# github: https://github.com/ccnicholls99/ptekwpdev.git
# ------------------------------------------------------------------------------
# Script: project_config_2.sh
#
# Synopsis:
#   Supplemental project configuration library (v2).
#
# Description:
#   Provides schema-driven validation, autoloading, safe accessors, and
#   project_add() for inserting validated project metadata into projects.json.
#
# Notes:
#   - Pure library (no side effects except explicit project_add writes)
#   - Autoloads project config when PTEK_PROJECT_KEY is set
#   - prjcfg() returns {{empty}} when config is not loaded
#   - Allows contributor-defined extra keys beyond the minimum schema
#
# ====<<Summary=================================================================

set -o errexit
set -o nounset
set -o pipefail

# ------------------------------------------------------------------------------
# Globals
# ------------------------------------------------------------------------------
declare -gA PTEKPRCFG=()          # Project config dictionary
declare -gA _PTEKPRCFG_MIN_KEYS=() # Required keys loaded from schema

# -----------------------------------------------------------------------------
# Resolve APP_BASE (canonical pattern)
# -----------------------------------------------------------------------------
PTEK_APP_BASE="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"
export PTEK_APP_BASE

# -----------------------------------------------------------------------------
# Prevent double-sourcing
# -----------------------------------------------------------------------------
[[ -n "${PTEK_LIB_PROJECT_CONFIG_LOADED:-}" ]] && return
PTEK_LIB_PROJECT_CONFIG_LOADED=1

# ====Error Handling>>=====================================
# Source Error Handling
# Generated Code, modify with caution
# =========================================================
_ts() { date +"%Y-%m-%d %H:%M:%S"; }
ptek_err() { COLOR_RED="\033[31m"; COLOR_RESET="\033[0m"; echo -e "${COLOR_RED}[$(_ts)] ERROR: $*${COLOR_RESET}" >&2; }

CALLER_PWD="$(pwd)"
trap 'ptek_err "Command failed (exit $?): $BASH_COMMAND"' ERR
trap 'cd "$CALLER_PWD" || true' EXIT
# ====<<Error Handling=====================================

# ====Log Handling>>=======================================
# Source Log Handling
# Set PTEK_LOGFILE before sourcing to set logfile (default=/dev/null)
# Else call set_log [options] <logfile>, post sourcing
# Generated Code, modify with caution
# =========================================================
# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/output.sh"
# ====<<Log Handling=======================================

# ====App Config>>=========================================
# Source App Configuration Library
# Defines PTEKWPCFG settngs dictionary. Adds appcfg 'key' accessor function
# Generated Code, modify with caution
# =========================================================
# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/app_config.sh"
# ====<<App Config=========================================

# ====Helpers>>============================================
# Source Helper Functions
# Generated Code, modify with caution
# =========================================================
# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/helpers.sh"
# ====<<Helpers============================================

# ------------------------------------------------------------------------------
# Load minimum required project keys
# ------------------------------------------------------------------------------
_PTEKPRCFG_SCHEMA_FILE="${PTEK_APP_BASE}/config/schema/prj_config_min_keys"

if [[ -f "$_PTEKPRCFG_SCHEMA_FILE" ]]; then
    while IFS= read -r key; do
        [[ -n "$key" ]] && _PTEKPRCFG_MIN_KEYS["$key"]=1
    done < "$_PTEKPRCFG_SCHEMA_FILE"
else
    error "Missing schema file: $_PTEKPRCFG_SCHEMA_FILE"
    exit 1
fi

# ------------------------------------------------------------------------------
# Private: Load project config into PTEKPRCFG
# ------------------------------------------------------------------------------
_project_config2_load() {
    local key="$1"
    local file
    file="$(appcfg config_base)/config/projects.json"

    if [[ ! -f "$file" ]]; then
        error "projects.json not found: $file"
        return 1
    fi

    # Extract project block
    local json
    json="$(jq -r --arg k "$key" '.projects[$k]' "$file")"

    if [[ "$json" == "null" ]]; then
        error "Project '$key' not found in $file"
        return 1
    fi

    # Flatten JSON into PTEKPRCFG
    while IFS='=' read -r k v; do
        PTEKPRCFG["$k"]="$v"
    done < <(
        jq -r '
            to_entries[] |
            "\(.key)=\(.value|tostring)"
        ' <<< "$json"
    )

    # Inject project_key
    PTEKPRCFG["project_key"]="$key"

    # Compute project_repo
    local base
    base="$(appcfg project_base)"

    local dir
    dir="${PTEKPRCFG[base_dir]}"

    # Normalize path
    local repo
    repo="$(realpath -m "${base}/${dir}")"

    PTEKPRCFG["project_repo"]="$repo"

    return 0
}

# ------------------------------------------------------------------------------
# Public accessor: prjcfg()
# Returns {{empty}} if config not loaded
# ------------------------------------------------------------------------------
prjcfg() {
    local key="$1"

    if [[ ${#PTEKPRCFG[@]} -eq 0 ]]; then
        printf '{{empty}}'
        return 0
    fi

    if [[ -n "${PTEKPRCFG[$key]+x}" ]]; then
        printf '%s' "${PTEKPRCFG[$key]}"
    else
        printf ''
    fi
}

# ------------------------------------------------------------------------------
# Public: project_add(key, dict)
#   - key: project key
#   - dict: JSON object (already validated by caller)
#   - Validates dict contains minimum required keys
# ------------------------------------------------------------------------------
project_add() {
    local key="$1"
    local dict="$2"

    local file
    file="$(appcfg config_base)/config/projects.json"

    if [[ ! -f "$file" ]]; then
        error "projects.json not found: $file"
        return 1
    fi

    # Validate required keys exist in dict
    local missing=false
    for req in "${!_PTEKPRCFG_MIN_KEYS[@]}"; do
        if ! jq -e --arg r "$req" 'has($r)' <<< "$dict" >/dev/null; then
            verror "Missing required project key: $req"
            missing=true
        fi
    done

    if [[ "$missing" == true ]]; then
        error "Project config missing required keys — aborting"
        return 1
    fi

    # Insert into JSON
    local tmp
    tmp="$(mktemp)"

    jq ".projects.\"${key}\" = ${dict}" "$file" > "$tmp"
    mv "$tmp" "$file"

    vsuccess "Project '$key' added to projects.json"
}

# ------------------------------------------------------------------------------
# Autoload if PTEK_PROJECT_KEY is set
# ------------------------------------------------------------------------------
if [[ -n "${PTEK_PROJECT_KEY:-}" ]]; then
    info "project_config_2: autoloading project '$PTEK_PROJECT_KEY'"
    _project_config2_load "$PTEK_PROJECT_KEY" || true
else
    info "project_config_2: no PTEK_PROJECT_KEY set — PTEKPRCFG remains empty"
fi