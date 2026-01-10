#!/usr/bin/env bash
# ====App Config Meta>>=========================================================
#  PTEKWPDEV — App Config Metadata Utility
#  Lists available configuration keys and dumps config state.
# ====<<App Config Meta=========================================================
set -Eeuo pipefail

# ------------------------------------------------------------------------------
# Resolve APP_BASE - must update relative path if script is moved! 
# ------------------------------------------------------------------------------
PTEK_APP_BASE="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd
)"
export PTEK_APP_BASE

# ------------------------------------------------------------------------------
# Load logging + config
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: app_config_meta.sh [--keys] [--dump] [-h]

Options:
  --keys     List all available configuration keys
  --dump     Dump all key/value pairs (secrets masked)
  -h         Show this help message

Examples:
  app_config_meta.sh --keys
  app_config_meta.sh --dump
EOF
}

# ------------------------------------------------------------------------------
# Parse args
# ------------------------------------------------------------------------------
MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keys) MODE="keys" ;;
    --dump) MODE="dump" ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

if [[ -z "$MODE" ]]; then
  usage
  exit 1
fi

# ------------------------------------------------------------------------------
# List keys
# ------------------------------------------------------------------------------
if [[ "$MODE" == "keys" ]]; then
  for k in "${!PTEKWPCFG[@]}"; do
    printf '%s\n' "$k"
  done | sort
  exit 0
fi

# ------------------------------------------------------------------------------
# Dump key/value pairs (with masking)
# ------------------------------------------------------------------------------
if [[ "$MODE" == "dump" ]]; then
  for k in "${!PTEKWPCFG[@]}"; do
    val="${PTEKWPCFG[$k]}"

    # Mask secrets.* keys
    if [[ "$k" == secrets.* ]]; then
      printf '%s=%s\n' "$k" "********"
    else
      printf '%s=%s\n' "$k" "$val"
    fi
  done | sort
  exit 0
fi

exit 0