#!/usr/bin/env bash
set -euo pipefail

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_BASE="${HOME}/.ptekwpdev"
CONFIG_FILE="${CONFIG_BASE}/environments.json"

# Source logging
if [[ -f "${APP_BASE}/lib/output.sh" ]]; then
  # shellcheck disable=SC1091
  source "${APP_BASE}/lib/output.sh"
else
  echo "[ERR] Missing lib/output.sh at ${APP_BASE}/lib/output.sh" >&2
  exit 1
fi

bootstrap_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    info "Creating base config file at $CONFIG_FILE"

    cat > "$CONFIG_FILE" <<'EOF'
{
    "app": {
        "build_home": "$HOME/ptekwpdev",
        "project_base": "$HOME/projects",
        "...": ""
    },
    "environments": {
        "project_name": "splatt",
        "project_title": "My new SPLATT site",
        "description": "Splatt Test WordPress development environment",
        "baseDir": "/ptekwpdev/splatt",     "_comment": "relative to app::PROJECT_BASE",
        "domain": "splatt.dev",             "_comment": "used in WP,PROXY, SSL certs, etc",
        "secrets": {
            "project_domain": "splatt.dev",
            "sqldb_name": "splattdb",
            "sqldb_user": "splattdbu",
            "sqldb_pass": "ChangeMe1!",
            "sqldb_root_pass": "ChangeMe1!",
            "wp_admin_user": "admin",
            "wp_admin_pass": "ChangeMe1!",
            "wp_admin_email": "admin@splatt.dev",
            "jwt_secret": "1234567890!@#$%^&*()"
        }
    }
}
EOF

    success "Base config file created"
  else
    warn "Config file already exists, skipping bootstrap"
  fi
}

setup_directories() {
  ensure_dir "$CONFIG_BASE/config"
  ensure_dir "$CONFIG_BASE/secrets"
  ensure_dir "$CONFIG_BASE/certs"
  ensure_dir "$CONFIG_BASE/assets"
}

# === MAIN ===
info "Initializing PtekWPDev workspace..."

bootstrap_config
setup_directories

success "Setup complete. Workspace ready at ${CONFIG_BASE}"