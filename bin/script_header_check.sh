#!/usr/bin/env bash
# ================================================================================
# PTEKWPDEV — a multi-project, bootstrap app for localized WordPress development
# github: https://github.com/ccnicholls99/ptekwpdev.git
# ------------------------------------------------------------------------------
# Script: script_header_check.sh
#
# Description:
#   Examine all scrips in APP_BASE/bin for comment headers
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
: "${PTEK_VERBOSE:=1}"
source "$APP_BASE/lib/output.sh"
mkdir -p "$APP_BASE/logs"
set_log --truncate "$APP_BASE/app/logs/script_header_check.log" "=== Script Header Check started at $(date) ==="

usage() {
  echo "Usage: script_header_check.sh <script1> [script2 ...]"
  exit 1
}

[[ $# -ge 1 ]] || usage

MISSING=0

for TARGET in "$@"; do
  if [[ ! -f "$TARGET" ]]; then
    error "File not found: $TARGET"
    MISSING=1
    continue
  fi

  # Skip line 1 (shebang), check line 2 for header marker
  HEADER_LINE="$(sed -n '2p' "$TARGET" || true)"

  if [[ "$HEADER_LINE" =~ ^#\ = ]]; then
    success "Header OK: $TARGET"
  else
    error "Missing header: $TARGET"
    MISSING=1
  fi
done

if [[ "$MISSING" -eq 1 ]]; then
  abort "One or more scripts are missing the required header"
fi

success "All scripts contain the required header"