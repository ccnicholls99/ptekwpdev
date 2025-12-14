#!/usr/bin/env bash
set -euo pipefail

# Resolve APP_BASE relative to script location
APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load helpers first (so warn/success/error are available)
source "${APP_BASE}/lib/output.sh"
source "${APP_BASE}/lib/helpers.sh"

ASSETS_DOCKER="${APP_BASE}/app/assets/docker"

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
  printf "\t-s, --src <path> e.g. path/to/assets/asset-file[.ext]\n"
  printf "\t-w, --what-if (dry run)\n\n"
  exit 1
}

# Logging setup
LOG_DIR="$APP_BASE/app/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/assets.log"
exec > >(tee -a "$LOG_FILE") 2>&1
warn "Starting assets script at $(date)"

# --- Functions for each action ---

build_assets() {
  run_or_preview "Build assets container from $ASSETS_DOCKER" \
    docker compose -f "${ASSETS_DOCKER}/compose.assets.yml" build ptekwpdev-assets

  run_or_preview "Start container so assets can be copied" \
    docker compose -f "${ASSETS_DOCKER}/compose.assets.yml" up -d ptekwpdev-assets

  CONTAINER_NAME="$(resolve_container_name "${ASSETS_DOCKER}/compose.assets.yml" ptekwpdev-assets)" || {
    error "Could not resolve container name after up"
    exit 1
  }
  require_container_up "$CONTAINER_NAME" 15 2

  echo "Copying existing assets from $APP_BASE/app/assets → $CONTAINER_NAME:/usr/src/ptekwpdev/assets"
  COPIED_ASSETS=()

  for type in plugins themes static; do
    SRC_DIR="${APP_BASE}/app/assets/${type}"
    DEST_DIR="/usr/src/ptekwpdev/assets/${type}"

if [[ -d "$SRC_DIR" ]]; then
  TMP_DIR="/tmp/assets-${type}"
  run_or_preview "Copy $type assets from $SRC_DIR → $DEST_DIR" \
    bash -c "docker cp \"$SRC_DIR/.\" \"$CONTAINER_NAME:$TMP_DIR\" && \
             docker exec \"$CONTAINER_NAME\" sh -c \"mkdir -p $DEST_DIR && cp -r $TMP_DIR/* $DEST_DIR/ && rm -rf $TMP_DIR\""

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
  run_or_preview "Start assets container" \
    docker compose -f "${ASSETS_DOCKER}/compose.assets.yml" up -d ptekwpdev-assets

  CONTAINER_NAME="$(resolve_container_name "${ASSETS_DOCKER}/compose.assets.yml" ptekwpdev-assets)" || {
    error "Could not resolve container name after up"
    exit 1
  }
  require_container_up "$CONTAINER_NAME" 15 2
  success "✅ Assets container '$CONTAINER_NAME' is running"
}

down_assets() {
  run_or_preview "Stop assets container" \
    docker compose -f "${ASSETS_DOCKER}/compose.assets.yml" down
  success "✅ Assets container stopped and removed"
}

copy_asset() {
  TYPE="$ASSET_TYPE"
  NAME="$ASSET_NAME"
  VERSION="$ASSET_VERSION"
  SRC="$ASSET_SRC"

  if [ -z "$TYPE" ]; then
    error "Missing required --type option (-t). Must be one of: plugin, theme, static."
    exit 1
  fi
  if [ -z "$NAME" ] || [ -z "$SRC" ]; then
    error "Missing required --name (-n) or --src (-s)."
    exit 1
  fi

  CONTAINER_NAME="$(resolve_container_name "${ASSETS_DOCKER}/compose.assets.yml" ptekwpdev-assets)" || {
    error "Could not resolve container name. Run: $0 -a up first."
    exit 1
  }
  require_container_up "$CONTAINER_NAME" 15 2

case "$TYPE" in
    plugin) TYPE_DIR="plugins" ;;
    theme)  TYPE_DIR="themes" ;;
    static) TYPE_DIR="static" ;;
    *)      error "Invalid type: $TYPE. Must be plugin, theme, or static."; exit 1 ;;
  esac

  DEST_DIR="/usr/src/ptekwpdev/assets/${TYPE_DIR}/${NAME}/${VERSION}"
  
  if [[ ! -f "$SRC" ]]; then
    error "Source asset not found: $SRC"
    exit 1
  fi

  run_or_preview "Copy $TYPE asset $NAME v$VERSION from $SRC → $CONTAINER_NAME:$DEST_DIR" \
    bash -c "docker cp \"$SRC\" \"$CONTAINER_NAME:/tmp/${NAME}-${VERSION}.zip\" && \
             docker exec \"$CONTAINER_NAME\" sh -c \"mkdir -p $DEST_DIR && mv /tmp/${NAME}-${VERSION}.zip $DEST_DIR/\""

  log_copy "$SRC" "$DEST_DIR"
  success "✅ Copied $TYPE asset $NAME v$VERSION into container"
}

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  if parse_what_if "$1"; then
    shift
    continue
  fi
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
  build)      build_assets ;;
  up)         up_assets ;;
  down)       down_assets ;;
  copy-asset) copy_asset ;;
  *)          usage ;;
esac