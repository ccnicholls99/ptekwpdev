#!/usr/bin/env bash
# ================================================================================
# PTEKWPDEV — a multi-project, bootstrap app for localized WordPress development
# github: https://github.com/ccnicholls99/ptekwpdev.git
# ------------------------------------------------------------------------------
# Script: asset_add.sh
#
# Description:
#   Installs local WORDPRESS assets (plugins, themes, static files) to the 
#   ASSETS volume available to all dev containers. (for example, PRO versions
#   of plugins or themes, not sourced from public wordpress repos) 
#
# Notes:
#   - If you teardown and remove the volume then you're on your own for
#     re-assembling all the bits and bobs back into the volume 
#
# ================================================================================
set -euo pipefail

# ---------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS_REPO="$APP_BASE/assets"
CONTAINER_NAME="ptekwpdev_assets"

# ---------------------------------------------------------
# Logging setup
# ---------------------------------------------------------
# Default to /dev/null until caller sets a real logfile
: "${PTEK_LOGFILE:=/dev/null}"
: "${PTEK_VERBOSE:=1}"

# Load logging utilities
source "$APP_BASE/lib/output.sh"

# ensure log dir exists and set logfile
mkdir -p "$APP_BASE/logs"
set_log --append "$APP_BASE/app/logs/script_header_check.log" "=== Script Header Check started at $(date) ==="

# ---------------------------------------------------------
# CLI parsing
# ---------------------------------------------------------
TYPE=""
NAME=""
VERSION=""
SRC=""

usage() {
  echo "Usage: $0 --type <plugin|theme|static> --name <asset-name> [--version <v>] [--src <path>]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) TYPE="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --src) SRC="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) abort "Unknown option: $1" ;;
  esac
done

[[ -n "$TYPE" ]] || abort "Missing required flag: --type"
[[ -n "$NAME" ]] || abort "Missing required flag: --name"

# ---------------------------------------------------------
# Determine source path
# ---------------------------------------------------------
if [[ -z "$SRC" ]]; then
  SRC="${ASSETS_REPO}/${TYPE}s/${NAME}"
fi

[[ -d "$SRC" ]] || abort "Source not found: $SRC"

# ---------------------------------------------------------
# Determine destination path inside container
# ---------------------------------------------------------
DEST="/var/www/assets/${TYPE}s/${NAME}"
[[ -n "$VERSION" ]] && DEST="${DEST}-${VERSION}"

info "Installing $TYPE [$NAME] (version: ${VERSION:-latest})"
info "Source: $SRC"
info "Destination: $CONTAINER_NAME:$DEST"

# ---------------------------------------------------------
# Perform copy
# ---------------------------------------------------------
if docker cp "$SRC" "$CONTAINER_NAME:$DEST"; then
  success "Installed $TYPE [$NAME] into assets container"
else
  abort "Failed to copy asset into container"
fi