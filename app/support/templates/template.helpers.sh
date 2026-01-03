#!/usr/bin/env bash
# ====Helpers>>============================================
# Source Helper Functions
# Generated Code, modify with caution
# =========================================================

if [[ -d "$PTEK_APP_BASE" ]]; then

    CHECK_FILE="${PTEK_APP_BASE}/lib/helpers.sh"

    if [[ ! -f "$CHECK_FILE" ]]; then
        echo "ERROR: Missing helper library at $CHECK_FILE"
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$CHECK_FILE"

else
    echo "ERROR: PTEK_APP_BASE not set or invalid: $PTEK_APP_BASE"
    exit 1
fi

# ====<<Helpers============================================