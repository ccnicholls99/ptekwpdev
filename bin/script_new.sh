#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
HEADER_TEMPLATE="$APP_BASE/doc/script_header.tpl"

usage() {
  echo "Usage: script_new.sh <script_path>"
  exit 1
}

[[ $# -eq 1 ]] || usage

TARGET="$1"

[[ -f "$HEADER_TEMPLATE" ]] || {
  echo "Header template not found: $HEADER_TEMPLATE" >&2
  exit 1
}

[[ -f "$TARGET" ]] || {
  echo "Target script does not exist: $TARGET" >&2
  exit 1
}

# Detect existing header (first line starts with '# ====')
if head -n 1 "$TARGET" | grep -q "^# ="; then
  echo "Script already has a header: $TARGET"
  exit 0
fi

echo "Inserting header into: $TARGET"

# Create a temp file
TMP="$(mktemp)"

# Write header + blank line + original content
cat "$HEADER_TEMPLATE" > "$TMP"
echo "" >> "$TMP"
cat "$TARGET" >> "$TMP"

# Replace original
mv "$TMP" "$TARGET"

echo "Header inserted."
