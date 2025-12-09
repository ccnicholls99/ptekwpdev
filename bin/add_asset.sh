#!/usr/bin/env bash
set -euo pipefail

ASSETS_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets" && pwd)"
CONTAINER_NAME="ptekwpdev_assets"

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
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[[ -n "$TYPE" ]] || { echo "Missing --type"; usage; }
[[ -n "$NAME" ]] || { echo "Missing --name"; usage; }

# Default source location
if [[ -z "$SRC" ]]; then
  SRC="${ASSETS_REPO}/${TYPE}s/${NAME}"
fi

[[ -d "$SRC" ]] || { echo "Source not found: $SRC"; exit 1; }

# Destination path inside container
DEST="/var/www/assets/${TYPE}s/${NAME}"
[[ -n "$VERSION" ]] && DEST="${DEST}-${VERSION}"

echo "Installing $TYPE [$NAME] (version: ${VERSION:-latest}) from $SRC → $CONTAINER_NAME:$DEST"

docker cp "$SRC" "$CONTAINER_NAME:$DEST"

echo "✅ Installed $TYPE [$NAME] into assets container"