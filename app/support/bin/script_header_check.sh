#!/usr/bin/env bash
# ================================================================================
# PTEKWPDEV — a multi-project, bootstrap app for localized WordPress development
# github: https://github.com/ccnicholls99/ptekwpdev.git
# ------------------------------------------------------------------------------
# Script: script_header_check.sh
#
# Description:
#   Examine all scripts in APP_BASE/bin for comment headers.
#
# Notes:
#   - Header Template can be found in APP_BASE/doc/script_header.tpl
#
# ================================================================================
#!/usr/bin/env bash
set -Eeuo pipefail

# --- Error Handling ---------------------------------------------------------
COLOR_RED="\033[31m"
COLOR_RESET="\033[0m"
_ts() { date +"%Y-%m-%d %H:%M:%S"; }
err() { echo -e "${COLOR_RED}[$(_ts)] ERROR: $*${COLOR_RESET}" >&2; }

CALLER_PWD="$(pwd)"
trap 'err "Command failed (exit $?): $BASH_COMMAND"' ERR
trap 'cd "$CALLER_PWD" || true' EXIT
# ---------------------------------------------------------------------------

# Resolve APP_BASE from app/support/bin
APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SUPPORT_BASE="${APP_BASE}/app/support"
TEMPLATE_DIR="${SUPPORT_BASE}/templates"
HEADER_TEMPLATE="${TEMPLATE_DIR}/script_header.tpl"

usage() {
    cat <<EOF
Usage: script_header_check.sh [options] <file1> [file2 ...]

Include verification flags:
  -e?   Verify error.sh include
  -l?   Verify output.sh include (requires LOGFILE guard)
  -u?   Verify helpers.sh include
  -a?   Verify app_config.sh include
  -p?   Verify project_config.sh include (requires PROJECT_KEY guard)

This script performs:
  - Header hash verification
  - Include block wrapper verification
  - Canonical include ordering checks
  - Guard checks for LOGFILE and PROJECT_KEY
  - Verification that lib scripts are sourced, not executed
EOF
    exit 1
}

# --- Parse include verification flags ---------------------------------------
declare -A VERIFY=()
declare -A INCLUDE_LINES=(
    [e]='source "${APP_BASE}/lib/error.sh"'
    [l]='source "${APP_BASE}/lib/output.sh"'
    [u]='source "${APP_BASE}/lib/helpers.sh"'
    [a]='source "${APP_BASE}/lib/app_config.sh"'
    [p]='source "${APP_BASE}/lib/project_config.sh"'
)
INCLUDE_ORDER=(e l u a p)

FILES=()

FILES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;

        -[eluap]\?)
            key="${1:1:1}"
            VERIFY["$key"]=1
            ;;

        -*)
            err "Unknown option: $1"
            usage
            ;;

        *)
            FILES+=("$1")
            ;;
    esac
    shift
done

[[ ${#FILES[@]} -gt 0 ]] || usage

# --- Compute canonical header hash ------------------------------------------
CANON_HASH="$(sha256sum "$HEADER_TEMPLATE" | awk '{print $1}')"

status=0

# --- Check each file --------------------------------------------------------
for file in "${FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        err "Not a file: $file"
        status=1
        continue
    fi

    echo "Checking: $file"

    # --- 1. Header verification ---------------------------------------------
    EXISTING_HASH="$(head -n 50 "$file" | sha256sum | awk '{print $1}')"
    if [[ "$EXISTING_HASH" != "$CANON_HASH" ]]; then
        err "Header mismatch: $file"
        status=1
    fi

    # --- 2. Extract include block -------------------------------------------
    include_block="$(sed -n '/^# --- Generated Includes/,/^# ---------------------------------------------------------------------------/p' "$file")"

    if [[ -z "$include_block" ]]; then
        err "Missing generated include block wrapper in $file"
        status=1
        continue
    fi

    # --- 3. Verify include ordering + presence -------------------------------
    for key in "${INCLUDE_ORDER[@]}"; do
        line="${INCLUDE_LINES[$key]}"

        if [[ -n "${VERIFY[$key]:-}" ]]; then
            if ! grep -Fq "$line" <<< "$include_block"; then
                err "Missing include ($key?): $line"
                status=1
            fi
        fi
    done

    # --- 4. Guard checks -----------------------------------------------------
    if grep -Fq 'source "${APP_BASE}/lib/output.sh"' <<< "$include_block"; then
        if ! grep -Fq 'LOGFILE' <<< "$include_block"; then
            err "Missing LOGFILE guard before output.sh in $file"
            status=1
        fi
    fi

    if grep -Fq 'source "${APP_BASE}/lib/project_config.sh"' <<< "$include_block"; then
        if ! grep -Fq 'PROJECT_KEY' <<< "$include_block"; then
            err "Missing PROJECT_KEY guard before project_config.sh in $file"
            status=1
        fi
    fi

    # --- 5. Verify lib scripts enforce sourced-only guard --------------------
    for key in "${INCLUDE_ORDER[@]}"; do
        line="${INCLUDE_LINES[$key]}"
        if grep -Fq "$line" <<< "$include_block"; then
            lib_path="$(sed 's/source "\(.*\)"/\1/' <<< "$line")"
            if ! grep -Fq 'BASH_SOURCE' "$lib_path"; then
                err "Lib script missing sourced-only guard: $lib_path"
                status=1
            fi
        fi
    done

    echo "OK: $file"
done

exit "$status"