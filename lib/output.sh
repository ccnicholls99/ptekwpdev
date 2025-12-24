#!/usr/bin/env bash
# Unified logging functions for PtekWPDev
# Prints to stdout (with colors) and appends to logfile

# --------------------------------------------------------------------
# LOGFILE contract
# --------------------------------------------------------------------
# - Must be set by the caller BEFORE sourcing this file.
# - Must be a path whose parent directory already exists.
# - This file will NOT create default paths or directories.
# - On violation, it prints an error to stderr and exits non-zero.
# --------------------------------------------------------------------

# Ensure LOGFILE is explicitly set
if [[ -z "${LOGFILE:-}" ]]; then
  echo "[ERROR] LOGFILE is not set. Set LOGFILE before sourcing output.sh." >&2
  exit 1
fi

# Ensure the parent directory of LOGFILE exists
LOGDIR="$(dirname "$LOGFILE")"
if [[ ! -d "$LOGDIR" ]]; then
  echo "[ERROR] LOGFILE directory does not exist: $LOGDIR" >&2
  echo "[ERROR] Create the directory or adjust LOGFILE before sourcing output.sh." >&2
  exit 1
fi

# ANSI color codes
COLOR_RESET="\033[0m"
COLOR_INFO="\033[34m"     # Blue
COLOR_SUCCESS="\033[32m"  # Green
COLOR_WARN="\033[33m"     # Yellow
COLOR_ERROR="\033[31m"    # Red
COLOR_DEBUG="\033[35m"    # Magenta
COLOR_WHATIF="\033[38;5;208m" # Orange (ANSI 256-color)

# Default verbosity: normal (1)
VERBOSE=1

# Parse CLI args for quiet/debug
for arg in "$@"; do
  case "$arg" in
    -q|--quiet) VERBOSE=0 ;;
    --debug)    VERBOSE=2 ;;
  esac
done

timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

log_header() {
  local process_name="$1"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

  echo "" >> "$LOGFILE"
  echo "==================================================" >> "$LOGFILE"
  echo ">>> START ${process_name} run at ${timestamp}" >> "$LOGFILE"
  echo "==================================================" >> "$LOGFILE"
  echo "" >> "$LOGFILE"
}

_log() {
  local level="$1"; shift
  local color="$1"; shift
  local msg="$*"
  local ts
  ts="$(timestamp)"

  # Decide whether to print based on verbosity
  case "$level" in
    INFO|SUCCESS|WARN) [[ "$VERBOSE" -ge 1 ]] || return ;;
    ERROR)             [[ "$VERBOSE" -ge 0 ]] || return ;;
    DEBUG)             [[ "$VERBOSE" -ge 2 ]] || return ;;
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
whatif()  { _log "WHAT-IF" "$COLOR_WHATIF"  "$*"; }
