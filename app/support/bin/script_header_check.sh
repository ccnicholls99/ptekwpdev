#!/usr/bin/env bash
# ================================================================================
# PTEKWPDEV — Header & Template Block Check Utility
# -------------------------------------------------------------------------------
# Checks whether a script contains the canonical header wrapper AND all expected
# mutation-aware template include blocks.
#
# This tool does NOT modify files.
#
# For template and header details, see:
#   app/support/README.md
# ================================================================================

set -Eeuo pipefail

# --- Error Handling ---------------------------------------------------------
COLOR_RED="\033[31m"
COLOR_GREEN="\033[32m"
COLOR_RESET="\033[0m"
_ts() { date +"%Y-%m-%d %H:%M:%S"; }
err() { echo -e "${COLOR_RED}[$(_ts)] ERROR: $*${COLOR_RESET}" >&2; }
ok()  { echo -e "${COLOR_GREEN}[$(_ts)] OK: $*${COLOR_RESET}"; }

CALLER_PWD="$(pwd)"
trap 'err "Command failed (exit $?): $BASH_COMMAND"' ERR
trap 'cd "$CALLER_PWD" || true' EXIT
# ---------------------------------------------------------------------------

# --- Flags -----------------------------------------------------------------
USE_VERBOSE=0
USE_WHATIF=0

usage() {
    cat <<EOF
Usage: script_header_check.sh [options] <script-path>

Options:
  -v, --verbose         Print success messages as well as failures
  -w, --what-if         Dry-run mode (no effect, but prints actions)
  -h, --help            Show this help message

Example:
  script_header_check.sh ./bin/wordpress_cleanup.sh
EOF
}
# ---------------------------------------------------------------------------

# --- Parse Args ------------------------------------------------------------
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) USE_VERBOSE=1 ;;
        -w|--what-if) USE_WHATIF=1 ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            err "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            ARGS+=("$1")
            ;;
    esac
    shift
done

[[ ${#ARGS[@]} -eq 1 ]] || { err "Missing script path"; usage; exit 1; }
TARGET="${ARGS[0]}"
# ---------------------------------------------------------------------------

# --- WHAT-IF Preview -------------------------------------------------------
if [[ $USE_WHATIF -eq 1 ]]; then
    echo "[WHAT-IF] Would check header and template blocks for: $TARGET"
fi
# ---------------------------------------------------------------------------

# --- Validate Target -------------------------------------------------------
if [[ ! -f "$TARGET" ]]; then
    err "File not found: $TARGET"
    exit 1
fi
# ---------------------------------------------------------------------------

# --- Header Wrapper Check --------------------------------------------------
HEADER_OPEN_REGEX='^# ====.+>>=+'
HEADER_CLOSE_REGEX='^# ====<<.+=+'

HAS_OPEN=0
HAS_CLOSE=0

HAS_OPEN=0
HAS_CLOSE=0

while IFS= read -r line; do
    [[ $line =~ $HEADER_OPEN_REGEX ]] && HAS_OPEN=1
    [[ $line =~ $HEADER_CLOSE_REGEX ]] && HAS_CLOSE=1
done < <(head -n 20 "$TARGET")

if [[ $HAS_OPEN -eq 0 || $HAS_CLOSE -eq 0 ]]; then
    err "Missing or invalid script header wrapper"
    exit 2
else
    [[ $USE_VERBOSE -eq 1 ]] && ok "Header wrapper OK"
fi
# ---------------------------------------------------------------------------

# --- Template Block Checks -------------------------------------------------
declare -A TEMPLATE_BLOCKS=(
    ["Error Handling"]="Error Handling"
    ["Log Handling"]="Log Handling"
    ["Helpers"]="Helpers"
    ["App Config"]="App Config"
    ["Project Config"]="Project Config"
)

MISSING=0

for KEY in "${!TEMPLATE_BLOCKS[@]}"; do
    NAME="${TEMPLATE_BLOCKS[$KEY]}"

    OPEN_PATTERN="# ====${NAME}>>"
    CLOSE_PATTERN="# ====<<${NAME}"

    HAS_OPEN=$(grep -c "$OPEN_PATTERN" "$TARGET" || true)
    HAS_CLOSE=$(grep -c "$CLOSE_PATTERN" "$TARGET" || true)

    if [[ $HAS_OPEN -gt 0 && $HAS_CLOSE -gt 0 ]]; then
        [[ $USE_VERBOSE -eq 1 ]] && ok "Template OK: $NAME"
    else
        err "Missing template block: $NAME"
        MISSING=1
    fi
done

# ---------------------------------------------------------------------------

if [[ $MISSING -eq 1 ]]; then
    exit 3
else
    [[ $USE_VERBOSE -eq 1 ]] && ok "All template blocks present"
    exit 0
fi