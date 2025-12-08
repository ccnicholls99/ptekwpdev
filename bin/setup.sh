#!/usr/bin/env bash
set -euo pipefail

# Target App Configuration in user/home
BUILD_HOME="$(dirname "$0")"
CONFIG_BASE="${HOME}/.ptekwpdev"
CONFIG_FILE="${CONFIG_BASE}/environments.json"

# Default verbosity: normal (1)
VERBOSE=1

usage() {
  echo "Usage: $0 [-q|--quiet] [-d|--debug] [-h|--help]"
  echo "  -q, --quiet    Quiet mode (only errors)"
  echo "  -d, --debug    Debug mode (verbose + debug messages)"
  echo "  -h, --help     Show this help message"
  exit 0
}

# === Unified option loop ===
while [[ $# -gt 0 ]]; do
  case "$1" in
    -q|--quiet) VERBOSE=0; shift ;;
    -d|--debug) VERBOSE=2; shift ;;
    -h|--help)  usage ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      ;;
    *)
      shift
      ;;
  esac
done

export VERBOSE

# Source logging functions
source "$BUILD_HOME/lib/output.sh"

ensure_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    info "Creating directory: $dir"
    mkdir -p "$dir"
  else
    success "Directory exists: $dir"
  fi
}

bootstrap_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    info "Creating base config file at $CONFIG_FILE"

    cat > "$CONFIG_FILE" <<'EOF'
{
    "app": {
        "build_home": "$BUILD_HOME",
        "project_base": "$HOME/projects",
    },
    "environments": {
        "project_name": "splatt",
        "project_title": "My new SPLATT site",
        "description": "Splatt Test WordPress development environment",
        "baseDir": "/ptekwpdev/splatt",     
        "domain": "splatt.dev",             
        "secrets": {
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
  # Ensure core directories exist
  ensure_dir "$CONFIG_BASE/config"

  # If config exists, read app-wide dirs
  if [[ -f "$CONFIG_FILE" ]]; then
    PROJECTS_BASE=$(jq -r '.app.project_base' "$CONFIG_FILE")

    ensure_dir "$PROJECTS_BASE"
  fi
}

# === MAIN ===
info "Initializing PtekWPDev CONFIG_BASE..."

bootstrap_config
setup_directories

success "Setup complete. CONFIG_BASE ready at ${CONFIG_BASE}"