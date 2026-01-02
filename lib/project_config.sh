#!/usr/bin/env bash
# ===================================================================
#  project_config.sh
#  Load project-level configuration from projects.json into a private
#  dictionary, exposing ONLY prjcfg() as a public accessor.
#
#  - Must be sourced, never executed
#  - Auto-loads when sourced
#  - Uses ONLY logging functions from APP_BASE/lib/output.sh
#  - No exports, no global leakage, no side effects
# ===================================================================

set -euo pipefail

# -------------------------------------------------------------------
# Ensure this file is sourced, not executed
# -------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "ERROR: project_config.sh must be sourced, not executed" >&2
    exit 1
fi

# -------------------------------------------------------------------
# Resolve APP_BASE and source global config + logging FIRST
# -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$APP_BASE/lib/app_config.sh"

# shellcheck source=/dev/null
source "$APP_BASE/lib/output.sh"

info "project_config.sh initialized (APP_BASE=$APP_BASE)"

# ---------------------------------------------------------------
# Public dictionary
# ---------------------------------------------------------------
declare -gA ptekprcfg=()

# -------------------------------------------------------------------
# Private scope: all internal functions and variables hidden
# -------------------------------------------------------------------
(

    # ---------------------------------------------------------------
    # Private: load project configuration
    # ---------------------------------------------------------------
    _project_config_load() {
        local key="$1"
        local file="${PTEKWPCFG[projects_file]}"

        if [[ -z "$key" ]]; then
            error "project_config_load: no project key provided"
            return 1
        fi

        if [[ ! -f "$file" ]]; then
            error "projects.json not found: $file"
            return 1
        fi

        info "Loading project '$key' from $file"

        local json
        json="$(jq -r --arg k "$key" '.projects[$k]' "$file")"

        if [[ "$json" == "null" ]]; then
            error "Project '$key' not found in $file"
            return 1
        fi

        # Flatten JSON into dictionary
        while IFS="=" read -r k v; do
            ptekprcfg["$k"]="$v"
        done < <(
            echo "$json" | jq -r '
                to_entries[] | "\(.key)=\(.value|tostring)"
            '
        )

        # Normalize base_dir (strip ALL leading slashes)
        if [[ -n "${ptekprcfg[base_dir]:-}" ]]; then
            local before="${ptekprcfg[base_dir]}"
            ptekprcfg[base_dir]="${before##/}"
            info "Normalized base_dir: '$before' → '${ptekprcfg[base_dir]}'"
        fi

        # Required fields
        local required=(project_title project_description base_dir)
        for r in "${required[@]}"; do
            if [[ -z "${ptekprcfg[$r]:-}" ]]; then
                error "Missing required project field: $r"
                return 1
            fi
        done

        # -----------------------------------------------------------
        # Compute project_repo with full normalization
        # -----------------------------------------------------------
        local raw_base="${PTEKWPCFG[project_base]}"
        local raw_dir="${ptekprcfg[base_dir]}"

        # Strip trailing slashes from project_base
        local clean_base="${raw_base%/}"

        # Strip leading slashes from base_dir
        local clean_dir="${raw_dir##/}"

        local repo="${clean_base}/${clean_dir}"
        ptekprcfg[project_repo]="$repo"

        # Inject project_key since it is not stored in JSON
        ptekprcfg[project_key]="$key"

        info "Computed project_repo: '$raw_base' + '$raw_dir' → '$repo'"

        success "Project '$key' configuration loaded"
    }

    # ---------------------------------------------------------------
    # Auto-load when sourced
    # ---------------------------------------------------------------
    if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
        if [[ -z "${PTEK_PROJECT_KEY:-}" ]]; then
            error "project_config.sh sourced but PTEK_PROJECT_KEY is not set"
            return 1
        fi

        info "Auto-loading project config for '$PTEK_PROJECT_KEY'"
        _project_config_load "$PTEK_PROJECT_KEY"
    fi
)

# -------------------------------------------------------------------
# Public accessor (ONLY public function)
# -------------------------------------------------------------------
prjcfg() {
    local key="$1"
    [[ -n "${ptekprcfg[$key]+x}" ]] && printf '%s' "${ptekprcfg[$key]}"
}