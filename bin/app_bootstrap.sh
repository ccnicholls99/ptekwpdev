#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — App Bootstrap Script (Final Hardened Version)
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail

# ------------------------------------------------------------------------------
# Preserve caller directory
# ------------------------------------------------------------------------------
PTEK_CALLER_PWD="$(pwd)"
ptekwp_cleanup() { cd "$PTEK_CALLER_PWD" || true; }
trap ptekwp_cleanup EXIT

# ------------------------------------------------------------------------------
# Resolve APP_BASE
# ------------------------------------------------------------------------------
APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ------------------------------------------------------------------------------
# Load logging utilities
# ------------------------------------------------------------------------------
if [[ -f "$APP_BASE/lib/output.sh" ]]; then
  # shellcheck source=/dev/null
  source "$APP_BASE/lib/output.sh"
else
  echo "$APP_BASE/lib/output.sh not found. Aborting."
  exit 1
fi

LOG_DIR="$APP_BASE/app/logs"
mkdir -p "$LOG_DIR"
set_log --truncate "$LOG_DIR/app_bootstrap.log" "=== App Bootstrap Run ($(date)) ==="

# ------------------------------------------------------------------------------
# Flags
# ------------------------------------------------------------------------------
CONFIG_BASE="$HOME/.ptekwpdev"
PROJECT_BASE="$HOME/ptekwpdev_repo"
WHAT_IF=false
NO_PROMPT=false
FORCE=false

print_usage() {
  echo "Usage: $0 [options]"
  echo "  --config-base <path>"
  echo "  --project-base <path>"
  echo "  -w | --what-if"
  echo "  -n | --no-prompt"
  echo "  -f | --force"
  echo "  -h | --help"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config-base) CONFIG_BASE="$2"; shift 2 ;;
    --project-base) PROJECT_BASE="$2"; shift 2 ;;
    -w|--what-if) WHAT_IF=true; shift ;;
    -n|--no-prompt) NO_PROMPT=true; shift ;;
    -f|--force) FORCE=true; shift ;;
    -h|--help) print_usage; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$CONFIG_BASE" ]]; then error "CONFIG_BASE cannot be empty."; exit 1; fi
if [[ -z "$PROJECT_BASE" ]]; then error "PROJECT_BASE cannot be empty."; exit 1; fi

if [[ "$WHAT_IF" == true ]]; then
  whatif "------------------------------------------------------------"
  whatif "  WHAT-IF MODE ENABLED — NO CHANGES WILL BE WRITTEN"
  whatif "------------------------------------------------------------"
fi

# ------------------------------------------------------------------------------
# Safe secret generator (ASCII-only, JSON-safe)
# ------------------------------------------------------------------------------
generate_secret() {
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 32 || true
}

generate_secret_keys() {
  
  info "Generating secrets key values..."

  SQLDB_ROOT_USER="root"
  if [[ "$WHAT_IF" == true ]]; then
    SQLDB_ROOT_PASS="**secret**"
    whatif "Dummy Secrets key values created"
  else
    SQLDB_ROOT_PASS="$(generate_secret)"
    success "Secrets key values created"
  fi

}

# ------------------------------------------------------------------------------
# JSON-safe string escaper (newline-safe)
# ------------------------------------------------------------------------------
json_escape() {
  printf '%s' "$1" | jq -R . | tr -d '\n'
}

# ------------------------------------------------------------------------------
# Paths
# ------------------------------------------------------------------------------
APP_JSON="$APP_BASE/app/config/app.json"
SCHEMA_PATH="$APP_BASE/app/config/schema/app.schema.json"

# ------------------------------------------------------------------------------
# Directory scaffolding
# ------------------------------------------------------------------------------
create_directory_structure() {
  info "Preparing directory structure..."

  REQUIRED_DIRS=(
    "$APP_BASE/app/config"
    "$CONFIG_BASE"
    "$CONFIG_BASE/config"
    "$PROJECT_BASE"
  )

  for dir in "${REQUIRED_DIRS[@]}"; do
    if [[ "$WHAT_IF" == true ]]; then
      whatif "WHAT-IF: Would create directory: $dir"
    else
      mkdir -p "$dir"
      info "Ensured: $dir"
    fi
  done
  
  #echo "DEBUG: after scaffolding, exit code=$?" >&2

  info "Directory scaffolding complete."
}

# ------------------------------------------------------------------------------
# Write app.json
# ------------------------------------------------------------------------------
write_app_json() {

  info "Generating app.json → $APP_JSON"
  local esc_pass
  esc_pass=$(json_escape "$SQLDB_ROOT_PASS")

  local json_content
  json_content="$(cat <<EOF
{
  "app_key": "ptekwpdev",
  "app_base": "$APP_BASE",
  "config_base": "$CONFIG_BASE",
  "project_base": "$PROJECT_BASE",

  "backend_network": "ptekwpdev_backend",

  "secrets": {
    "sqldb_root": "$SQLDB_ROOT_USER",
    "sqldb_root_pass": $esc_pass
  },

  "database": {
    "sqldb_port": "3306",
    "sqldb_image": "mariadb",
    "sqldb_version": "10.5",

    "sqladmin_image": "phpmyadmin/phpmyadmin",
    "sqladmin_version": "latest",
    "sqladmin_port": "5211"
  },

  "assets": {
    "container": "ptekwpdev_assets",
    "root_path": "/usr/src/ptekwpdev/assets"
  },

  "wordpress_defaults": {
    "image": "wordpress:latest",
    "php_version": "8.2",
    "port": 8080,
    "ssl_port": "8443"
  }
}
EOF
)"

  if [[ "$WHAT_IF" == true ]]; then
    whatif "WHAT-IF: Would write app.json:"
    whatif "$json_content"
    return 0
  fi

  if [[ -f "$APP_JSON" && "$FORCE" != true ]]; then
    error "$APP_JSON already exists. Use --force to overwrite."
    exit 1
  fi

  # TODO: Re-enable schema validation once Ajv meta-schema handling is fixed.
  # validate_schema "$json_content"

  echo "$json_content" > "$APP_JSON"
  success "Wrote app.json → $APP_JSON"
}

# ------------------------------------------------------------------------------
# Deploy to CONFIG_BASE
# ------------------------------------------------------------------------------
deploy_app_config() {
  local dest="$CONFIG_BASE/config/app.json"

  if [[ "$WHAT_IF" == true ]]; then
    whatif "WHAT-IF: Would copy $APP_JSON → $dest"
    return 0
  fi

  cp "$APP_JSON" "$dest"
  success "CONFIG_BASE initialized at $dest"
}

# ------------------------------------------------------------------------------
# Orchestrator
# ------------------------------------------------------------------------------
bootstrap_app() {
  create_directory_structure
  generate_secret_keys
  write_app_json
  deploy_app_config
}

bootstrap_app
success "App bootstrap complete."