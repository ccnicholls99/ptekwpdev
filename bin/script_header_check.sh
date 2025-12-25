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
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------
# Logging setup
# ---------------------------------------------------------
: "${PTEK_LOGFILE:=/dev/null}"
PTEK_VERBOSE=0   # default: quiet mode (errors only)

# Parse verbosity flag
for arg in "$@"; do
  case "$arg" in
    -v|--verbose) PTEK_VERBOSE=1 ;;
  esac
done

source "$APP_BASE/lib/output.sh"

# Ensure logs directory exists
mkdir -p "$APP_BASE/app/logs"

set_log --truncate "$APP_BASE/app/logs/script_header_check.log" \
        "+--- Starting Script Header Check at $(date) ---+"

usage() {
  echo "Usage: script_header_check.sh [-v|--verbose] <script1> [script2 ...]"
  exit 1
}

# Strip out -v/--verbose from args before processing file list
ARGS=()
for arg in "$@"; do
  case "$arg" in
    -v|--verbose) ;;  # skip
    *) ARGS+=("$arg") ;;
  esac
done

[[ ${#ARGS[@]} -ge 1 ]] || usage

MISSING=0

for TARGET in "${ARGS[@]}"; do
  if [[ ! -f "$TARGET" ]]; then
    error "File not found: $TARGET"
    MISSING=1
    continue
  fi

  # Skip shebang, check line 2
  HEADER_LINE="$(sed -n '2p' "$TARGET" || true)"

  if [[ "$HEADER_LINE" =~ ^#\ = ]]; then
    # Only print success in verbose mode
    if [[ "$PTEK_VERBOSE" -ge 1 ]]; then
      success "Header OK: $TARGET"
    fi
  else
    error "Missing header: $TARGET"
    MISSING=1
  fi
done

if [[ "$MISSING" -eq 1 ]]; then
  abort "One or more scripts are missing the required header"
fi

# Only print final success in verbose mode
if [[ "$PTEK_VERBOSE" -ge 1 ]]; then
  success "All scripts contain the required header"
fi