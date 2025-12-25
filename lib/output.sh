#!/usr/bin/env bash
# Unified logging functions for PtekWPDev
# Prints to stdout (with colors) and appends to logfile

# --------------------------------------------------------------------
# LOGFILE contract (updated)
# --------------------------------------------------------------------
# - PTEK_LOGFILE is optional.
# - If unset, logging goes to /dev/null (safe for early bootstrap).
# - If set, its parent directory MUST exist.
# - This file will NOT create directories.
# --------------------------------------------------------------------

# Collision-proof logfile variable
: "${PTEK_LOGFILE:=/dev/null}"

# Validate directory only if not /dev/null
if [[ "$PTEK_LOGFILE" != "/dev/null" ]]; then
  LOGDIR="$(dirname "$PTEK_LOGFILE")"
  if [[ ! -d "$LOGDIR" ]]; then
    echo "[ERROR] PTEK_LOGFILE directory does not exist: $LOGDIR" >&2
    echo "[ERROR] Create the directory or adjust PTEK_LOGFILE before sourcing output.sh." >&2
    exit 1
  fi
fi

# ANSI color codes
COLOR_RESET="\033[0m"
COLOR_INFO="\033[34m"
COLOR_SUCCESS="\033[32m"
COLOR_WARN="\033[33m"
COLOR_ERROR="\033[31m"
COLOR_DEBUG="\033[35m"
COLOR_WHATIF="\033[38;5;208m"

# Default verbosity: normal (1), if not specified
# PTEK_VERBOSE=1
: "${PTEK_VERBOSE:=1}"

timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

log_header() {
  local process_name="$1"
  local ts
  ts="$(timestamp)"

  echo "" >> "$PTEK_LOGFILE"
  echo "==================================================" >> "$PTEK_LOGFILE"
  echo ">>> START ${process_name} run at ${ts}" >> "$PTEK_LOGFILE"
  echo "==================================================" >> "$PTEK_LOGFILE"
  echo "" >> "$PTEK_LOGFILE"
}

_log() {
  local level="$1"; shift
  local color="$1"; shift
  local msg="$*"
  local ts
  ts="$(timestamp)"

  # Verbosity rules
  case "$level" in
    INFO|SUCCESS|WARN) [[ "$PTEK_VERBOSE" -ge 1 ]] || return ;;
    ERROR)             [[ "$PTEK_VERBOSE" -ge 0 ]] || return ;;
    DEBUG)             [[ "$PTEK_VERBOSE" -ge 2 ]] || return ;;
  esac

  # Print to stdout
  echo -e "${color}[${ts}] [${level}]${COLOR_RESET} $msg"

  # Append to logfile (if not /dev/null)
  echo "[${ts}] [${level}] $msg" >> "$PTEK_LOGFILE"
}

info()    { _log "INFO"    "$COLOR_INFO"    "$*"; }
success() { _log "SUCCESS" "$COLOR_SUCCESS" "$*"; }
warn()    { _log "WARN"    "$COLOR_WARN"    "$*"; }
error()   { _log "ERROR"   "$COLOR_ERROR"   "$*"; }
debug()   { _log "DEBUG"   "$COLOR_DEBUG"   "$*"; }
whatif()  { _log "WHAT-IF" "$COLOR_WHATIF"  "$*"; }

# Hard failure: log + exit
abort() {
  error "$*"
  _log "FAIL" "$COLOR_ERROR" "Command terminated"
  exit 1
}

set_log() {
  local mode=""
  local logfile=""
  local header=""

  case "${1:-}" in
    --append)
      mode="append"
      logfile="$2"
      header="${3:-}"
      ;;
    --truncate)
      mode="truncate"
      logfile="$2"
      header="${3:-}"
      ;;
    *)
      error "set_log(): usage: set_log --append <file> [header] | set_log --truncate <file> [header]"
      return 1
      ;;
  esac

  if [[ -z "$logfile" ]]; then
    error "set_log(): missing logfile argument"
    return 1
  fi

  local logdir
  logdir="$(dirname "$logfile")"

  if [[ ! -d "$logdir" ]]; then
    error "set_log(): directory does not exist: $logdir"
    return 1
  fi

  if ! touch "$logfile" 2>/dev/null; then
    error "set_log(): cannot write to logfile: $logfile"
    return 1
  fi

  if [[ "$mode" == "truncate" ]]; then
    : > "$logfile"
  fi

  PTEK_LOGFILE="$logfile"

  # Only print success if verbose mode is enabled
  if [[ "${PTEK_VERBOSE:-1}" -ge 1 ]]; then
    success "Logfile set to: $PTEK_LOGFILE (mode: $mode)"
  fi

  if [[ -n "$header" ]]; then
    echo "$header" >> "$PTEK_LOGFILE"
  fi
}