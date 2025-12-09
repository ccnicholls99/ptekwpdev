#!/usr/bin/env bash
set -euo pipefail

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_BASE="${HOME}/.ptekwpdev"
CONFIG_FILE="${CONFIG_BASE}/environments.json"
TPL_FILE="${APP_BASE}/config/environments.tpl.json"

# Must run from APP_BASE
if [[ "$PWD" != "$APP_BASE" ]]; then
  echo "[ERR] Must run from APP_BASE: $APP_BASE"
  echo "      Current directory: $PWD"
  exit 1
fi

mkdir -p "${CONFIG_BASE}"

LOG_FILE="${CONFIG_BASE}/setup.log"
source "${APP_BASE}/lib/output.sh"
source "${APP_BASE}/lib/helpers.sh"

bootstrap_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    info "Bootstrapping environments.json from template"
    if [[ -f "$TPL_FILE" ]]; then
      expand_env_file "$TPL_FILE" "$CONFIG_FILE"
      success "Config file created at $CONFIG_FILE"
    else
      error "Missing template file: $TPL_FILE"
      exit 1
    fi
  else
    warn "Config file already exists, creating backup before overwrite"
    backup_config "$CONFIG_FILE"
    expand_env_file "$TPL_FILE" "$CONFIG_FILE"
    success "Config file refreshed from template"
  fi
}


setup_directories() {
  ensure_dir "$CONFIG_BASE/config"
  ensure_dir "$CONFIG_BASE/secrets"
  ensure_dir "$CONFIG_BASE/certs"
  ensure_dir "$CONFIG_BASE/assets"
}

info "Initializing PtekWPDev workspace..."
bootstrap_config
setup_directories
success "Setup complete. Workspace ready at ${CONFIG_BASE}"
