#!/usr/bin/env bash
set -euo pipefail

# Resolve APP_BASE relative to script location
APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DOCKER="${APP_BASE}/app/assets/docker"
ASSETS_REPO="${APP_BASE}/assets"
CONTAINER_NAME="ptekwpdev_assets"

ACTION=""
ASSET_TYPE=""
ASSET_NAME=""
ASSET_VERSION=""
ASSET_SRC=""

usage() {
  echo "Usage: $0 --action <build|up|copy-plugin|copy-theme> [--type <plugin|theme|static>] [--name <asset>] [--version <v>] [--src <path>]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action) ACTION="$2"; shift 2 ;;
    --type) ASSET_TYPE="$2"; shift 2 ;;
    --name) ASSET_NAME="$2"; shift 2 ;;
    --version) ASSET_VERSION="$2"; shift 2 ;;
    --src) ASSET_SRC="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

case "$ACTION" in
  build)
    echo "Building assets container from $ASSETS_DOCKER"
    docker compose -f "${ASSETS_DOCKER}/compose.assets.yml" build ptekwpdev-assets
    ;;
  up)
    echo "Starting assets container"
    docker compose -f "${ASSETS_DOCKER}/compose.assets.yml" up -d ptekwpdev-assets
    ;;
  copy-plugin|copy-theme)
    [[ -n "$ASSET_TYPE" ]] || { echo "Missing --type"; usage; }
    [[ -n "$ASSET_NAME" ]] || { echo "Missing --name"; usage; }

    # Default source location
    if [[ -z "$ASSET_SRC" ]]; then
      ASSET_SRC="${ASSETS_REPO}/${ASSET_TYPE}s/${ASSET_NAME}"
    fi

    [[ -d "$ASSET_SRC" ]] || { echo "Source not found: $ASSET_SRC"; exit 1; }

    DEST="/var/www/assets/${ASSET_TYPE}s/${ASSET_NAME}"
    [[ -n "$ASSET_VERSION" ]] && DEST="${DEST}-${ASSET_VERSION}"

    echo "Copying $ASSET_TYPE [$ASSET_NAME] (version: ${ASSET_VERSION:-latest}) from $ASSET_SRC → $CONTAINER_NAME:$DEST"
    docker cp "$ASSET_SRC" "$CONTAINER_NAME:$DEST"
    echo "✅ Installed $ASSET_TYPE [$ASSET_NAME] into assets container"
    ;;
  *)
    usage
    ;;
esac