#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — Bootstrap initializer for the app-level environment
#  Script: app_bootstrap.sh
#
#  Description:
#    First-run initializer executed immediately after git clone.
#    Establishes PTEK_APP_BASE, PTEK_CONFIG_BASE, PTEK_PROJECT_BASE and writes
#    app/config/ptekwpdev.json as the static app-level configuration file.
#
#  Contract:
#    - Never destructive without explicit confirmation
#    - Never touches project-level config
#    - Never launches Docker or WordPress
#    - Always restores caller's working directory
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail

# ------------------------------------------------------------------------------
# Preserve caller directory
# ------------------------------------------------------------------------------

PTEK_CALLER_PWD="$(pwd)"
ptekwp_cleanup() { cd "$PTEK_CALLER_PWD"; }
trap ptekwp_cleanup EXIT

# ------------------------------------------------------------------------------
# Resolve PTEK_APP_BASE (scripts always run from APP_BASE/bin)
# ------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PTEK_APP_BASE="$(cd "${SCRIPT_DIR}/.." && pwd)"
PTEK_APP_KEY="$(basename "$PTEK_APP_BASE")"

# ------------------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------------------

NO_PROMPT=false
OVERWRITE=false

DEFAULT_PTEK_CONFIG_BASE="${HOME}/.${PTEK_APP_KEY}"
DEFAULT_PTEK_PROJECT_BASE="${HOME}/${PTEK_APP_KEY}/projects"

PTEK_CONFIG_BASE=""
PTEK_PROJECT_BASE=""

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -n, --no-prompt         Run non-interactively using defaults or provided args
  --overwrite             Allow overwrite in --no-prompt mode
  --config-base PATH      Override PTEK_CONFIG_BASE
  --project-base PATH     Override PTEK_PROJECT_BASE
  -h, --help              Show this help message

Defaults:
  PTEK_APP_BASE     = ${PTEK_APP_BASE}
  PTEK_CONFIG_BASE  = ${DEFAULT_PTEK_CONFIG_BASE}
  PTEK_PROJECT_BASE = ${DEFAULT_PTEK_PROJECT_BASE}
EOF
}

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

prompt() {
  local var_name="$1"
  local prompt_text="$2"
  local default_value="$3"

  local value=""
  read -rp "${prompt_text} [${default_value}]: " value
  value="${value:-$default_value}"

  printf -v "$var_name" '%s' "$value"
}

normalize_path() {
  local path="$1"
  mkdir -p "$path"
  (
    cd "$path"
    pwd
  )
}

# ------------------------------------------------------------------------------
# Argument parsing
# ------------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--no-prompt)
      NO_PROMPT=true
      ;;
    --overwrite)
      OVERWRITE=true
      ;;
    --config-base)
      shift
      PTEK_CONFIG_BASE="$1"
      ;;
    --project-base)
      shift
      PTEK_PROJECT_BASE="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

# ------------------------------------------------------------------------------
# Interactive or script-mode value resolution
# ------------------------------------------------------------------------------

if [[ "$NO_PROMPT" == false ]]; then
  echo "Bootstrapping ${PTEK_APP_KEY} in interactive mode."
  echo "PTEK_APP_BASE detected as: ${PTEK_APP_BASE}"
  echo

  prompt PTEK_CONFIG_BASE  "Enter PTEK_CONFIG_BASE"  "${DEFAULT_PTEK_CONFIG_BASE}"
  prompt PTEK_PROJECT_BASE "Enter PTEK_PROJECT_BASE" "${DEFAULT_PTEK_PROJECT_BASE}"
else
  echo "Bootstrapping ${PTEK_APP_KEY} in script mode (--no-prompt)."

  PTEK_CONFIG_BASE="${PTEK_CONFIG_BASE:-$DEFAULT_PTEK_CONFIG_BASE}"
  PTEK_PROJECT_BASE="${PTEK_PROJECT_BASE:-$DEFAULT_PTEK_PROJECT_BASE}"
fi

# ------------------------------------------------------------------------------
# Normalize paths (safe, does not change caller directory)
# ------------------------------------------------------------------------------

PTEK_CONFIG_BASE="$(normalize_path "$PTEK_CONFIG_BASE")"
PTEK_PROJECT_BASE="$(normalize_path "$PTEK_PROJECT_BASE")"

# ------------------------------------------------------------------------------
# Prepare directories
# ------------------------------------------------------------------------------

PTEK_APP_CONFIG_DIR="${PTEK_APP_BASE}/app/config"
mkdir -p "$PTEK_APP_CONFIG_DIR"

APP_JSON_FILE="${PTEK_APP_CONFIG_DIR}/${PTEK_APP_KEY}.json"

# ------------------------------------------------------------------------------
# Handle existing config file
# ------------------------------------------------------------------------------

if [[ -f "$APP_JSON_FILE" ]]; then
  if [[ "$NO_PROMPT" == false ]]; then
    echo "Config file already exists:"
    echo "  $APP_JSON_FILE"
    read -rp "Overwrite? (y/N): " answer
    answer="${answer,,}"
    if [[ "$answer" != "y" && "$answer" != "yes" ]]; then
      echo "Aborting. Existing config preserved."
      exit 0
    fi
  else
    if [[ "$OVERWRITE" != true ]]; then
      echo "ERROR: Config file exists and --overwrite not provided:"
      echo "  $APP_JSON_FILE"
      echo "Use: --overwrite   (only valid with --no-prompt)"
      exit 1
    fi
  fi
fi

# ------------------------------------------------------------------------------
# Write minimal ptekwpdev.json
# ------------------------------------------------------------------------------

cat > "$APP_JSON_FILE" <<EOF
{
  "APP_KEY": "${PTEK_APP_KEY}",
  "APP_BASE": "${PTEK_APP_BASE}",
  "CONFIG_BASE": "${PTEK_CONFIG_BASE}",
  "PROJECT_BASE": "${PTEK_PROJECT_BASE}",
  "assets": {
    "container": "ptekwpdev_assets",
    "root_path": "/usr/src/ptekwpdev/assets"
  }
}
EOF

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo
echo "Bootstrap complete. App configuration written to: ${APP_JSON_FILE}"