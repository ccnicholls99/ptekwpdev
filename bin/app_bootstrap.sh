#!/usr/bin/env bash
# ====App Bootstrap>>===========================================================
# Initializes the PTEKWPDEV application environment.
# - Loads existing app.json or initializes from schema template
# - Applies overrides from app.config (flat key=value)
# - Expands only $HOME and ~ (no other env expansion)
# - Reports changes (verbose)
# - Backs up existing app.json before overwrite
# - Warns on empty-string or -1 values
# - Computes APP_BASE, CONFIG_BASE, PROJECT_BASE from final JSON
# - Creates required directories
# - Safe by default; destructive actions require --force
# ====<<App Bootstrap===========================================================

set -Eeuo pipefail

# ====Error Handling>>=====================================
COLOR_RED="\033[31m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RESET="\033[0m"
_ts() { date +"%Y-%m-%d %H:%M:%S"; }
err()  { echo -e "${COLOR_RED}[$(_ts)] ERROR: $*${COLOR_RESET}" >&2; }
ok()   { echo -e "${COLOR_GREEN}[$(_ts)] OK: $*${COLOR_RESET}"; }
warn() { echo -e "${COLOR_YELLOW}[$(_ts)] WARN: $*${COLOR_RESET}"; }

CALLER_PWD="$(pwd)"
trap 'err "Command failed (exit $?): $BASH_COMMAND"' ERR
trap 'cd "$CALLER_PWD" || true' EXIT
# ====<<Error Handling=====================================

# ---------------------------------------------------------------------------
# Resolve APP_BASE (canonical pattern)
# ---------------------------------------------------------------------------
PTEK_APP_BASE="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"
export PTEK_APP_BASE

# --- Flags ------------------------------------------------------------------
USE_VERBOSE=0
USE_WHATIF=0
USE_FORCE=0

usage() {
    cat <<EOF
Usage: app_bootstrap.sh [options]

Options:
  -v, --verbose         Enable verbose output
  -w, --what-if         Dry-run mode (preview actions, no changes)
  -f, --force           Force rewrite of app.json even if unchanged
  -h, --help            Show this help message

Description:
  Initializes the PTEKWPDEV application environment by loading app.json or
  initializing it from schema, applying overrides from app.config (flat KVP),
  reporting changes, backing up existing config, and ensuring required
  directories exist.
EOF
}

# --- Parse Arguments ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) USE_VERBOSE=1 ;;
        -w|--what-if) USE_WHATIF=1 ;;
        -f|--force)   USE_FORCE=1 ;;
        -h|--help)    usage; exit 0 ;;
        -*) err "Unknown option: $1"; usage; exit 1 ;;
        *)  err "Unexpected argument: $1"; usage; exit 1 ;;
    esac
    shift
done

# --- Paths -------------------------------------------------------------------
APP_JSON_PATH="$PTEK_APP_BASE/app/config/app.json"
USER_CONFIG_FILE="$PTEK_APP_BASE/app/config/app.config"
TEMPLATE_JSON="$PTEK_APP_BASE/app/config/schema/app.tpl.json"

mkdir -p "$PTEK_APP_BASE/app/config"

# --- HOME-only expansion helper ----------------------------------------------
expand_home_only() {
    local v="$1"

    # Expand leading ~
    if [[ "$v" == "~"* ]]; then
        v="${v/#~/$HOME}"
    fi

    # Expand literal $HOME only
    v="${v//\$HOME/$HOME}"

    echo "$v"
}

# --- Step 1: Load or initialize app.json ------------------------------------
if [[ -f "$APP_JSON_PATH" ]]; then
    BASE_JSON=$(cat "$APP_JSON_PATH")
    [[ $USE_VERBOSE -eq 1 ]] && ok "Loaded existing app.json"
else
    if [[ $USE_WHATIF -eq 1 ]]; then
        echo "[WHAT-IF] Would initialize app.json from template → $TEMPLATE_JSON"
        BASE_JSON=$(cat "$TEMPLATE_JSON")
    else
        cp "$TEMPLATE_JSON" "$APP_JSON_PATH"
        BASE_JSON=$(cat "$APP_JSON_PATH")
        [[ $USE_VERBOSE -eq 1 ]] && ok "Initialized app.json from template"
    fi
fi

MERGED_JSON="$BASE_JSON"

# --- Step 2: Apply overrides from app.config (flat KVP) ----------------------
if [[ -f "$USER_CONFIG_FILE" ]]; then
    [[ $USE_VERBOSE -eq 1 ]] && ok "Applying overrides from app.config"

    while IFS='=' read -r RAW_KEY RAW_VALUE; do
        # Skip comments and blank lines
        [[ "$RAW_KEY" =~ ^# ]] && continue
        [[ -z "$RAW_KEY" ]] && continue

        KEY=$(echo "$RAW_KEY" | xargs)
        VALUE=$(echo "$RAW_VALUE" | xargs)

        # Expand only $HOME and ~
        VALUE=$(expand_home_only "$VALUE")

        # Apply override using jq dotted-path update
        MERGED_JSON=$(echo "$MERGED_JSON" | jq --arg v "$VALUE" ".$KEY = \$v")

        [[ $USE_VERBOSE -eq 1 ]] && echo "  ~ $KEY = $VALUE"

    done < "$USER_CONFIG_FILE"

else
    [[ $USE_VERBOSE -eq 1 ]] && ok "No app.config found; using base values only"
fi

# Determine if anything changed
if [[ "$(echo "$BASE_JSON" | jq -S .)" != "$(echo "$MERGED_JSON" | jq -S .)" ]]; then
    HAS_CHANGES=1
else
    HAS_CHANGES=0
fi

# Decide whether to write
if [[ $HAS_CHANGES -eq 1 || $USE_FORCE -eq 1 ]]; then
    DO_WRITE=1
else
    DO_WRITE=0
fi

# --- Step 3: Backup existing app.json (if rewriting) -------------------------
if [[ -f "$APP_JSON_PATH" && $DO_WRITE -eq 1 ]]; then
    TS="$(date +"%Y%m%d-%H%M%S")"
    BACKUP_FILE="${APP_JSON_PATH}.${TS}.bak"

    if [[ $USE_WHATIF -eq 1 ]]; then
        echo "[WHAT-IF] Would back up existing app.json → $BACKUP_FILE"
    else
        cp "$APP_JSON_PATH" "$BACKUP_FILE"
        [[ $USE_VERBOSE -eq 1 ]] && ok "Backed up existing app.json → $BACKUP_FILE"
    fi
fi

# --- Step 4: Write merged app.json -------------------------------------------
if [[ $DO_WRITE -eq 1 ]]; then
    if [[ $USE_WHATIF -eq 1 ]]; then
        echo "[WHAT-IF] Would write merged app.json → $APP_JSON_PATH"
    else
        echo "$MERGED_JSON" > "$APP_JSON_PATH"
        [[ $USE_VERBOSE -eq 1 ]] && ok "Wrote merged app.json"
    fi
else
    [[ $USE_VERBOSE -eq 1 ]] && warn "Skipped writing app.json (no changes and no --force)"
fi

# --- Step 5: Warn on empty-string or -1 values -------------------------------
EMPTY_KEYS=$(echo "$MERGED_JSON" | jq -r '
  to_entries | map(select(.value == "")) | .[]?.key
')

NEG1_KEYS=$(echo "$MERGED_JSON" | jq -r '
  to_entries | map(select(.value == -1)) | .[]?.key
')

if [[ -n "$EMPTY_KEYS" ]]; then
    warn "The following keys have empty string values:"
    echo "$EMPTY_KEYS" | sed 's/^/  - /'
fi

if [[ -n "$NEG1_KEYS" ]]; then
    warn "The following keys have value -1:"
    echo "$NEG1_KEYS" | sed 's/^/  - /'
fi

# --- Step 6: Compute paths from merged JSON ----------------------------------
APP_BASE=$(jq -r '.app_base' "$APP_JSON_PATH")
CONFIG_BASE=$(jq -r '.config_base' "$APP_JSON_PATH")
PROJECT_BASE=$(jq -r '.project_base' "$APP_JSON_PATH")

[[ $USE_VERBOSE -eq 1 ]] && ok "Computed paths from app.json"

# --- Step 7: Ensure required directories exist -------------------------------
for DIR in "$CONFIG_BASE" "$PROJECT_BASE" "$APP_BASE/app/logs"; do
    if [[ $USE_WHATIF -eq 1 ]]; then
        echo "[WHAT-IF] Would create directory: $DIR"
    else
        mkdir -p "$DIR"
        [[ $USE_VERBOSE -eq 1 ]] && ok "Created directory: $DIR"
    fi
done

# --- Final Output -------------------------------------------------------------
if [[ $USE_WHATIF -eq 1 ]]; then
    ok "[WHAT-IF] Bootstrap completed (no changes made)."
else
    ok "Bootstrap completed successfully."
fi