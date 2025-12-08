#!/usr/bin/env bash
set -euo pipefail

# Paths
WORKSPACE_ROOT="${HOME}/.ptekwpdev"
CONFIG_FILE="${WORKSPACE_ROOT}/workspaces.json"   # written by setup.sh; matches cp_environments.json
# If you prefer to point directly at cp_environments.json during testing:
# CONFIG_FILE="${WORKSPACE_ROOT}/cp_environments.json"

VERBOSE=1
WORKSPACE_NAME=""
PROJECT_NAME=""

usage() {
  echo "Usage: $0 [-q|--quiet] [-d|--debug] [--workspace <name>] [--project <name>]"
  echo "  -q, --quiet           Quiet mode (errors only)"
  echo "  -d, --debug           Debug mode (verbose logs)"
  echo "  --workspace <name>    Workspace identifier (used for directory structure)"
  echo "  --project <name>      Project name (defaults from JSON if omitted)"
  exit 1
}

# === Unified option loop ===
while [[ $# -gt 0 ]]; do
  case "$1" in
    -q|--quiet) VERBOSE=0; shift ;;
    -d|--debug) VERBOSE=2; shift ;;
    -h|--help)  usage ;;
    --workspace)
      [[ $# -ge 2 ]] || { echo "Error: --workspace requires a value"; usage; }
      WORKSPACE_NAME="$2"; shift 2 ;;
    --project)
      [[ $# -ge 2 ]] || { echo "Error: --project requires a value"; usage; }
      PROJECT_NAME="$2"; shift 2 ;;
    -*)
      echo "Unknown option: $1"; usage ;;
    *)
      # Ignore positional arguments for now
      shift ;;
  esac
done

export VERBOSE
# Source your logging functions (info/warn/success/error)
# Expected at ~/.ptekwpdev/lib/output.sh
if [[ -f "${WORKSPACE_ROOT}/lib/output.sh" ]]; then
  # shellcheck disable=SC1090
  source "${WORKSPACE_ROOT}/lib/output.sh"
else
  # Minimal fallback loggers
  info()    { echo "[INFO] $*"; }
  warn()    { echo "[WARN] $*"; }
  success() { echo "[OK]   $*"; }
  error()   { echo "[ERR]  $*" >&2; }
fi

# === Helpers ===
ensure_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
    info "Created: $dir"
  fi
}

copy_dir_safe() {
  local src="$1"
  local dest="$2"
  ensure_dir "$(dirname "$dest")"
  if [[ -d "$dest" ]]; then
    info "Already exists, refreshing contents: $dest"
  else
    info "Copying: $src -> $dest"
  fi
  # Copy preserving template structure; overwrite files to ensure freshness
  rsync -a --delete "$src/" "$dest/"
}

# === Validate config ===
if [[ ! -f "$CONFIG_FILE" ]]; then
  error "Missing config file: $CONFIG_FILE"
  exit 1
fi

# Extract app values
BUILD_HOME=$(jq -r '.app.build_home' "$CONFIG_FILE")
PROJECT_BASE=$(jq -r '.app.project_base' "$CONFIG_FILE")

# Extract environment defaults
JSON_PROJECT_NAME=$(jq -r '.environments.project_name' "$CONFIG_FILE")
JSON_DOMAIN=$(jq -r '.environments.domain' "$CONFIG_FILE")
JSON_BASEDIR=$(jq -r '.environments.baseDir' "$CONFIG_FILE")

# Choose effective names
PROJECT_NAME="${PROJECT_NAME:-$JSON_PROJECT_NAME}"
if [[ -z "$WORKSPACE_NAME" ]]; then
  # Default workspace: use the environment project_name as shorthand
  WORKSPACE_NAME="$JSON_PROJECT_NAME"
fi

# Compose target path:
# $PROJECT_BASE/$WORKSPACE_NAME/$PROJECT_NAME/
TARGET_ROOT="${PROJECT_BASE}/${WORKSPACE_NAME}/${PROJECT_NAME}"
DOCKER_SRC="${WORKSPACE_ROOT}/config/docker"
DOCKER_DEST="${TARGET_ROOT}/docker"
CONFIG_SRC_ROOT="${WORKSPACE_ROOT}/config"
CONFIG_DEST_ROOT="${DOCKER_DEST}/config"

info "Provisioning:"
info "  Workspace:  $WORKSPACE_NAME"
info "  Project:    $PROJECT_NAME"
info "  Domain:     $JSON_DOMAIN"
info "  ProjectBase:$PROJECT_BASE"
info "  TargetRoot: $TARGET_ROOT"

# === Create directory structure ===
ensure_dir "$TARGET_ROOT"
ensure_dir "$DOCKER_DEST"
ensure_dir "$CONFIG_DEST_ROOT"
ensure_dir "${CONFIG_DEST_ROOT}/apache"   # empty apache dir per your layout

# === Copy docker base (env.tpl → .env) ===
if [[ ! -d "$DOCKER_SRC" ]]; then
  error "Missing docker templates at: ${DOCKER_SRC}"
  exit 1
fi
copy_dir_safe "$DOCKER_SRC" "$DOCKER_DEST"

# Environments secrets (for envsubst)
PROJECT_DOMAIN=$(jq -r '.environments.secrets.project_domain' "$CONFIG_FILE")
SQLDB_NAME=$(jq -r '.environments.secrets.sqldb_name' "$CONFIG_FILE")
SQLDB_USER=$(jq -r '.environments.secrets.sqldb_user' "$CONFIG_FILE")
SQLDB_PASS=$(jq -r '.environments.secrets.sqldb_pass' "$CONFIG_FILE")
SQLDB_ROOT_PASS=$(jq -r '.environments.secrets.sqldb_root_pass' "$CONFIG_FILE")
WP_ADMIN_USER=$(jq -r '.environments.secrets.wp_admin_user' "$CONFIG_FILE")
WP_ADMIN_PASS=$(jq -r '.environments.secrets.wp_admin_pass' "$CONFIG_FILE")
WP_ADMIN_EMAIL=$(jq -r '.environments.secrets.wp_admin_email' "$CONFIG_FILE")
JWT_SECRET=$(jq -r '.environments.secrets.jwt_secret' "$CONFIG_FILE")

export PROJECT_DOMAIN SQLDB_NAME SQLDB_USER SQLDB_PASS SQLDB_ROOT_PASS WP_ADMIN_USER WP_ADMIN_PASS WP_ADMIN_EMAIL JWT_SECRET

# Generate .env from env.tpl
if [[ -f "${DOCKER_DEST}/env.tpl" ]]; then
  info "Generating .env from env.tpl"
  envsubst < "${DOCKER_DEST}/env.tpl" > "${DOCKER_DEST}/.env"
  rm -f "${DOCKER_DEST}/env.tpl"
  success ".env generated at ${DOCKER_DEST}/.env"
else
  warn "env.tpl not found under ${DOCKER_DEST}; skipping .env generation"
fi

# === Copy service configs into docker/config ===
for service in wordpress sqldb sqladmin proxy wpcli; do
  local_src="${CONFIG_SRC_ROOT}/${service}"
  local_dest="${CONFIG_DEST_ROOT}/${service}"
  if [[ -d "$local_src" ]]; then
    copy_dir_safe "$local_src" "$local_dest"
    success "Provisioned ${service} config"
  else
    warn "Missing ${service} templates at ${local_src}; created empty directory"
    ensure_dir "$local_dest"
  fi
done

# Ensure specific files are present per your spec:
# - wordpress/ptek-resources.ini (from config/wordpress/)
# - proxy/nginx.conf.tpl (from config/proxy/)
# - wpcli/wpcli.Dockerfile (from config/wpcli/)
[[ -f "${CONFIG_DEST_ROOT}/wordpress/ptek-resources.ini" ]] || warn "wordpress/ptek-resources.ini missing in destination"
[[ -f "${CONFIG_DEST_ROOT}/proxy/nginx.conf.tpl" ]] || warn "proxy/nginx.conf.tpl missing in destination"
[[ -f "${CONFIG_DEST_ROOT}/wpcli/wpcli.Dockerfile" ]] || warn "wpcli/wpcli.Dockerfile missing in destination"

# === Scaffold fixed files at docker/config root ===
touch "${CONFIG_DEST_ROOT}/wordpress.Dockerfile"
touch "${CONFIG_DEST_ROOT}/compose.build.yml"
touch "${CONFIG_DEST_ROOT}/.dockerignore"
success "Scaffolded wordpress.Dockerfile, compose.build.yml, .dockerignore"

# === SSL cert directory (optional, if you want early generation) ===
CERTS_DIR="${WORKSPACE_ROOT}/certs/${JSON_DOMAIN}"
ensure_dir "$CERTS_DIR"
if [[ ! -f "${CERTS_DIR}/cert.pem" ]]; then
  info "Generating self-signed SSL cert for ${JSON_DOMAIN}"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "${CERTS_DIR}/key.pem" \
    -out "${CERTS_DIR}/cert.pem" \
    -subj "/CN=${JSON_DOMAIN}"
  success "SSL cert created at ${CERTS_DIR}"
else
  info "SSL cert already exists at ${CERTS_DIR}"
fi

success "Provisioning complete: ${TARGET_ROOT}"