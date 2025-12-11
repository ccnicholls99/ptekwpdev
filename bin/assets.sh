#!/usr/bin/env bash
set -euo pipefail

# Resolve APP_BASE relative to script location
APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_BASE="${HOME}/.ptekwpdev"
CONFIG_FILE="${CONFIG_BASE}/environments.json"

source "${APP_BASE}/lib/output.sh"
source "${APP_BASE}/lib/helpers.sh"

ASSETS_DOCKER="${APP_BASE}/app/assets/docker"
ASSETS_REPO="${APP_BASE}/assets"
CONTAINER_NAME="ptekwpdev_assets"

ACTION=""
ASSET_TYPE=""
ASSET_NAME=""
ASSET_VERSION="none"
ASSET_SRC=""

usage() {
  printf "Usage: %s\n" "$0"
  printf "\t-a, --action [ build | up | down | copy-asset ]\n"
  printf "\t-t, --type [ plugin | theme | static ]\n"
  printf "\t-n, --name <asset>\n"
  printf "\t-v, --version <v> (default: none)\n"
  printf "\t-s, --src <path> (default: \$ASSETS_REPO/<type>s/<name>)\n\n"
  exit 1
}

# --- Functions for each action ---

build_assets() {
  echo "Building assets container from $ASSETS_DOCKER"
  docker compose -f "${ASSETS_DOCKER}/compose.assets.yml" build ptekwpdev-assets

  echo "Starting container so assets can be copied"
  docker compose -f "${ASSETS_DOCKER}/compose.assets.yml" up -d ptekwpdev-assets

  echo "Copying existing assets from $APP_BASE/app/assets → $CONTAINER_NAME:/usr/src/ptekwpdev/assets"
  COPIED_ASSETS=()

  for type in plugins themes static; do
    SRC_DIR="${APP_BASE}/app/assets/${type}"
    DEST_DIR="/usr/src/ptekwpdev/assets/${type}"

    if [[ -d "$SRC_DIR" ]]; then
      TMP_DIR="/tmp/assets-${type}"
      docker cp "$SRC_DIR" "$CONTAINER_NAME:$TMP_DIR"
      docker exec "$CONTAINER_NAME" sh -c "mkdir -p $DEST_DIR && cp -r $TMP_DIR/* $DEST_DIR/ && rm -rf $TMP_DIR"

      log_copy "$SRC_DIR" "$DEST_DIR"
      COPIED_ASSETS+=("$type: $(ls -1 "$SRC_DIR" | xargs)")
      success "✅ Copied $type assets into container"
    else
      warn "No $type assets found in $SRC_DIR"
    fi
  done

  echo ""
  echo "📋 Post-build asset summary:"
  if [[ ${#COPIED_ASSETS[@]} -eq 0 ]]; then
    echo "No assets were copied."
  else
    for entry in "${COPIED_ASSETS[@]}"; do
      echo " - $entry"
    done
  fi
}


up_assets() {
  # Check if container is already running
  if docker ps --filter "name=$CONTAINER_NAME" --filter "status=running" | grep -q "$CONTAINER_NAME"; then
    success "✅ Assets container '$CONTAINER_NAME' is already running"
  else
    echo "Starting assets container"
    docker compose -f "${ASSETS_DOCKER}/compose.assets.yml" up -d ptekwpdev-assets
    success "✅ Assets container started"
  fi
}

down_assets() {
  echo "Stopping assets container"
  docker compose -f "${ASSETS_DOCKER}/compose.assets.yml" down
  success "✅ Assets container stopped and removed"
}

copy_asset() {
  [[ -n "$ASSET_TYPE" ]] || { echo "Missing --type"; usage; }
  [[ -n "$ASSET_NAME" ]] || { echo "Missing --name"; usage; }

  if [[ -z "$ASSET_SRC" ]]; then
    ASSET_SRC="${ASSETS_REPO}/${ASSET_TYPE}s/${ASSET_NAME}"
  fi

  [[ -e "$ASSET_SRC" ]] || { warn "Source not found: $ASSET_SRC"; exit 1; }

  DEST="/usr/src/ptekwpdev/assets/${ASSET_TYPE}s/${ASSET_NAME}"
  if [[ -n "$ASSET_VERSION" && "$ASSET_VERSION" != "none" ]]; then
    DEST="${DEST}/${ASSET_VERSION}"
  fi

  ensure_dir "$DEST"
  log_copy "$ASSET_SRC" "$DEST"

  echo "Copying $ASSET_TYPE [$ASSET_NAME] (version: ${ASSET_VERSION:-latest}) from $ASSET_SRC → $CONTAINER_NAME:$DEST"
  docker cp "$ASSET_SRC" "$CONTAINER_NAME:$DEST"
  success "✅ Installed $ASSET_TYPE [$ASSET_NAME] (version: ${ASSET_VERSION:-latest}) into assets container"
}

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--action)   ACTION="$2"; shift 2 ;;
    -t|--type)     ASSET_TYPE="$2"; shift 2 ;;
    -n|--name)     ASSET_NAME="$2"; shift 2 ;;
    -v|--version)  ASSET_VERSION="$2"; shift 2 ;;
    -s|--src)      ASSET_SRC="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# --- Dispatcher ---
case "$ACTION" in
  build) build_assets ;;
  up)    up_assets ;;
  down)  down_assets ;;
  copy-asset) copy_asset ;;
  *) usage ;;
esac  