#!/usr/bin/env bash
set -euo pipefail

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_BASE="${HOME}/.ptekwpdev"
CONFIG_FILE="${CONFIG_BASE}/environments.json"

# Must run from APP_BASE
if [[ "$PWD" != "$APP_BASE" ]]; then
  echo "[ERR] Must run from APP_BASE: $APP_BASE"
  echo "      Current directory: $PWD"
  exit 1
fi

mkdir -p "${CONFIG_BASE}"

LOG_FILE="${CONFIG_BASE}/provision.log"
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

# Require --project
if [[ -z "$PROJECT_KEY" ]]; then
  error "Missing required --project argument"
  usage
fi

# Ensure config exists
[[ -f "$CONFIG_FILE" ]] || { error "Missing config file: $CONFIG_FILE"; exit 1; }

# Extract project subsection
PROJECT_NAME=$(jq -r ".environments[\"$PROJECT_KEY\"].project_name" "$CONFIG_FILE")

# Safety: prevent overwriting app code
if [[ "$PROJECT_NAME" == "$(basename "$APP_BASE")" ]]; then
  error "Project name '$PROJECT_NAME' conflicts with APP_BASE ($(basename "$APP_BASE"))."
  error "Provisioning aborted to protect application source code."
  echo "[ERR] Provisioning blocked: project_name '$PROJECT_NAME' equals APP_BASE" >> "$CONFIG_BASE/setup.log"
  exit 1
fi

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
info "Resolved PROJECT_BASE: $PROJECT_BASE"
info "Target root: $TARGET_ROOT"
info "Config path: $CONFIG_DEST"
info "Docker path: $DOCKER_DEST"

# Build token map with lowercase keys
declare -A TOKENS
build_token_map() {
  # Secrets (normalize to lowercase)
  while IFS='=' read -r k v; do
    [[ -n "$k" ]] && TOKENS["${k,,}"]="$v"
  done < <(jq -r ".environments[\"$PROJECT_KEY\"].secrets | to_entries | .[] | \"\(.key)=\(.value)\"" "$CONFIG_FILE")

  # Project metadata (normalize to lowercase)
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

# Ensure project root and subdirs
ensure_dir "$TARGET_ROOT"
ensure_dir "$CONFIG_DEST"
ensure_dir "$DOCKER_DEST"

# Copy service configs from APP_BASE/config
for service in wordpress sqldb sqladmin proxy wpcli; do
  ensure_dir "$CONFIG_DEST/$service"
  cp -r "${APP_BASE}/config/${service}/"* "$CONFIG_DEST/$service/" 2>/dev/null || true
done

# Copy docker templates (except env.tpl) from APP_BASE/config/docker
DOCKER_SRC="${APP_BASE}/config/docker"
DOCKER_FILES=( "wordpress.Dockerfile" "compose.build.yml" ".dockerignore" )

copied_files=()
missing_files=()

for f in "${DOCKER_FILES[@]}"; do
  src="${DOCKER_SRC}/$f"
  dest="${DOCKER_DEST}/$f"

  if [[ -f "$src" ]]; then
    cp "$src" "$dest"
    copied_files+=("$f")
    info "Copied $f → $DOCKER_DEST"
  else
    missing_files+=("$f")
    warn "Missing docker template: $f (looked in $DOCKER_SRC)"
  fi
done

# Generate .env from env.tpl in APP_BASE/config/docker
ENV_TPL="${DOCKER_SRC}/env.tpl"
ENV_DEST="${DOCKER_DEST}/.env"
build_token_map
if [[ -f "$ENV_TPL" ]]; then
  generate_env_file_from_caret_tokens "$ENV_TPL" "$ENV_DEST"
else
  warn "env.tpl not found in $DOCKER_SRC"
fi

# Summary log
if [[ ${#copied_files[@]} -gt 0 ]]; then
  success "Docker templates copied: ${copied_files[*]}"
fi
if [[ ${#missing_files[@]} -gt 0 ]]; then
  warn "Templates not found in $DOCKER_SRC: ${missing_files[*]}"
fi

success "Provisioning complete for project [$PROJECT_KEY] → name: $PROJECT_NAME"