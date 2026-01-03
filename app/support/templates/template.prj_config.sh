#!/usr/bin/env bash
# ====Project Config>>=====================================
# Source Project Configuration Library
# Defines PTEKPRCFG[] dictionary and prjcfg() accessor
# Generated Code, modify with caution
# =========================================================

if [[ -d "$PTEK_APP_BASE" ]]; then

    CHECK_FILE="${PTEK_APP_BASE}/lib/project_config.sh"

    if [[ ! -f "$CHECK_FILE" ]]; then
        echo "ERROR: Missing project config library at $CHECK_FILE"
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$CHECK_FILE"

else
    echo "ERROR: PTEK_APP_BASE not set or invalid: $PTEK_APP_BASE"
    exit 1
fi

# ====<<Project Config=====================================