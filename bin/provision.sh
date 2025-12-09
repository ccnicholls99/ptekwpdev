#!/usr/bin/env bash
set -euo pipefail

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_BASE="${HOME}/.ptekwpdev"
CONFIG_FILE="${CONFIG_BASE}/environments.json"

source "${APP_BASE}/lib/output.sh"
source "${APP_BASE}/lib/helpers.sh"

PROJECT_KEY=""

usage() {
  echo "Usage: $0 --project <key>"
  exit 1
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT_KEY="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) error "Unknown option: $1"; usage ;;
  esac
done

[[ -n "$PROJECT_KEY" ]] || { error "Missing --project"; usage; }
[[ -f "$CONFIG_FILE" ]] || { error "Missing config file: $CONFIG_FILE"; exit 1; }

PROJECT_NAME=$(jq -r ".environments[\"$PROJECT_KEY\"].project_name" "$CONFIG_FILE")
PROJECT_TITLE=$(jq -r ".environments[\"$PROJECT_KEY\"].project_title" "$CONFIG_FILE")
PROJECT_DESC=$(jq -r ".environments[\"$PROJECT_KEY\"].description" "$CONFIG_FILE")
PROJECT_DOMAIN=$(jq -r ".environments[\"$PROJECT_KEY\"].domain" "$CONFIG_FILE")

PROJECT_BASE=$(jq -r '.app.project_base' "$CONFIG_FILE")
PROJECT_BASE="${PROJECT_BASE/\$HOME/$HOME}"

TARGET_ROOT="${PROJECT_BASE}/${PROJECT_NAME}"
CONFIG_DEST="${TARGET_ROOT}/config"
DOCKER_DEST="${TARGET_ROOT}/docker"

info "Provisioning project [$PROJECT_KEY] → name: $PROJECT_NAME"
info "Title: $PROJECT_TITLE"
info "Description: $PROJECT_DESC"
info "Domain: $PROJECT_DOMAIN"
info "Target root: $TARGET_ROOT"

# Build token map (lowercase keys)
declare -A TOKENS
build_token_map() {
  while IFS='=' read -r k v; do
    [[ -n "$k" ]] && TOKENS["${k,,}"]="$v"
  done < <(jq -r ".environments[\"$PROJECT_KEY\"].secrets | to_entries | .[] | \"\(.key)=\(.value)\"" "$CONFIG_FILE")

  TOKENS["project_name"]="$PROJECT_NAME"
  TOKENS["project_title"]="$PROJECT_TITLE"
  TOKENS["project_desc"]="$PROJECT_DESC"
  TOKENS["project_domain"]="$PROJECT_DOMAIN"
}

generate_env_file_from_caret_tokens() {
  local tpl="$1"
  local dest="$2"

  [[ -f "$tpl" ]] || { error "env.tpl not found at $tpl"; return 1; }

  local content
  content="$(<"$tpl")"

  for key in "${!TOKENS[@]}"; do
    local val="${TOKENS[$key]}"
    content="${content//^$key^/$val}"
  done

  mapfile -t unresolved < <(grep -oE '\^[A-Za-z0-9_]+\^' <<< "$content" | sort -u || true)

  printf "%s\n" "$content" > "$dest"
  success ".env generated at ${dest}"

  if [[ ${#unresolved[@]} -gt 0 ]]; then
    warn "Unresolved tokens in ${dest}: ${unresolved[*]}"
    warn "Source env template: ${tpl}"
  fi
}

# Ensure dirs
ensure_dir "$TARGET_ROOT"
ensure_dir "$CONFIG_DEST"
ensure_dir "$DOCKER_DEST"

# Copy service configs
for service in wordpress sqldb sqladmin proxy wpcli; do
  ensure_dir "$CONFIG_DEST/$service"
  cp -r "${APP_BASE}/config/${service}/"* "$CONFIG_DEST/$service/" 2>/dev/null || true
done

# Copy docker templates (except env.tpl)
DOCKER_SRC="${APP_BASE}/config/docker"
DOCKER_FILES=( "wordpress.Dockerfile" "compose.build.yml" ".dockerignore" )

for f in "${DOCKER_FILES[@]}"; do
  src="${DOCKER_SRC}/$f"
  dest="${DOCKER_DEST}/$f"
  if [[ -f "$src" ]]; then
    cp "$src" "$dest"
    success "Copied $f → $DOCKER_DEST"
  else
    warn "Missing docker template: $f (looked in $DOCKER_SRC)"
  fi
done

# Generate .env from env.tpl
ENV_TPL="${DOCKER_SRC}/env.tpl"
ENV_DEST="${DOCKER_DEST}/.env"
build_token_map
if [[ -f "$ENV_TPL" ]]; then
  generate_env_file_from_caret_tokens "$ENV_TPL" "$ENV_DEST"
else
  warn "env.tpl not found in $DOCKER_SRC"
fi

# Copy ptek-resources.ini into docker/config/wordpress
DOCKER_CONFIG_WORDPRESS="${DOCKER_DEST}/config/wordpress"
ensure_dir "$DOCKER_CONFIG_WORDPRESS"

RESOURCES_SRC="${APP_BASE}/config/wordpress/ptek-resources.ini"
RESOURCES_DEST="${DOCKER_CONFIG_WORDPRESS}/ptek-resources.ini"

if [[ -f "$RESOURCES_SRC" ]]; then
  cp "$RESOURCES_SRC" "$RESOURCES_DEST"
  success "Copied ptek-resources.ini → ${RESOURCES_DEST}"
else
  warn "Missing ptek-resources.ini in ${APP_BASE}/config/wordpress"
fi

success "Provisioning complete for project [$PROJECT_KEY] → name: $PROJECT_NAME"