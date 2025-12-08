#!/usr/bin/env bash
# Unified logging functions for PtekWPDev
# Prints to stdout (with colors) and appends to logfile

LOGFILE="${LOGFILE:-${HOME}/.ptekwpdev/setup.log}"

# ANSI color codes
COLOR_RESET="\033[0m"
COLOR_INFO="\033[34m"     # Blue
COLOR_SUCCESS="\033[32m"  # Green
COLOR_WARN="\033[33m"     # Yellow
COLOR_ERROR="\033[31m"    # Red
COLOR_DEBUG="\033[35m"    # Magenta

# Default verbosity: normal (1)
VERBOSE=1

# Parse CLI args for quiet/debug
for arg in "$@"; do
  case "$arg" in
    -q|--quiet)
      VERBOSE=0
      ;;
    --debug)
      VERBOSE=2
      ;;
  esac
done

timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

_log() {
  local level="$1"; shift
  local color="$1"; shift
  local msg="$*"
  local ts
  ts="$(timestamp)"

  # Decide whether to print based on verbosity
  case "$level" in
    INFO|SUCCESS|WARN)
      [[ "$VERBOSE" -ge 1 ]] || return
      ;;
    ERROR)
      [[ "$VERBOSE" -ge 0 ]] || return
      ;;
    DEBUG)
      [[ "$VERBOSE" -ge 2 ]] || return
      ;;
  esac

  # Print to stdout with color
  echo -e "${color}[${ts}] [${level}]${COLOR_RESET} $msg"

  # Append to logfile without color codes
  echo "[${ts}] [${level}] $msg" >> "$LOGFILE"
}

info()    { _log "INFO"    "$COLOR_INFO"    "$*"; }
success() { _log "SUCCESS" "$COLOR_SUCCESS" "$*"; }
warn()    { _log "WARN"    "$COLOR_WARN"    "$*"; }
error()   { _log "ERROR"   "$COLOR_ERROR"   "$*"; }
debug()   { _log "DEBUG"   "$COLOR_DEBUG"   "$*"; }