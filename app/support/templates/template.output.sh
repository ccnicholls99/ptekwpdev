#!/usr/bin/env bash
# ====Log Handling>>=======================================
# Source Log Handling
# Generated Code, modify with caution
# LOGFILE defaults to /dev/null unless PTEK_LOGFILE is set
# To change logfile: set_log [options] <logfile>
# =========================================================
if [[ -d "$PTEK_APP_BASE" ]]; then

    CHECK_FILE="${PTEK_APP_BASE}/lib/output.sh"

    if [[ ! -f "$CHECK_FILE" ]]; then
        echo "ERROR: Missing logging library at $CHECK_FILE"
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$CHECK_FILE"

else
    echo "ERROR: PTEK_APP_BASE not set or invalid: $PTEK_APP_BASE"
    exit 1
fi
# ==<<Log Handling=========================================