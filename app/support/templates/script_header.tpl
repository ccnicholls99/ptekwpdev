# ================================================================================
# PTEKWPDEV — a multi-project, bootstrap app for localized WordPress development
# github: https://github.com/ccnicholls99/ptekwpdev.git
# ------------------------------------------------------------------------------
# Script: {{script_name}}
#
# Description:
#   {{script_description}}
#
# Notes:
#   {{optional_notes}}
#
# ================================================================================
# --- Error Handling ---------------------------------------------------------
# Enable strict mode with ERR inheritance so traps fire inside functions.
set -Eeuo pipefail

# Capture the caller's working directory so EXIT can restore it.
PTEK_CALLER_PWD="$(pwd)"

# ANSI color for red
COLOR_RED="\033[31m"
COLOR_RESET="\033[0m"

# Timestamp helper
_ts() {
    date +"%Y-%m-%d %H:%M:%S"
}

# ERR trap: runs immediately when any command fails under set -e.
_ptekwp_err_handler() {
    local exit_code=$?
    local failed_cmd=$BASH_COMMAND
    local failed_pwd=$PWD
    local ts="$(_ts)"

    # Print directly to stderr, in red, with timestamp
    echo -e "${COLOR_RED}[${ts}] ERROR: Command failed (exit ${exit_code}): ${failed_cmd}${COLOR_RESET}" >&2
    echo -e "${COLOR_RED}[${ts}] ERROR: PWD at failure: ${failed_pwd}${COLOR_RESET}" >&2
}

# EXIT trap: always runs, success or failure.
_ptekwp_exit_handler() {
    local exit_code=$?
    cd "${PTEK_CALLER_PWD}" 2>/dev/null || true
}

trap _ptekwp_err_handler ERR
trap _ptekwp_exit_handler EXIT
# ---------------------------------------------------------------------------