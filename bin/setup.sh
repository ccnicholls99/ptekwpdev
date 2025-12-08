#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="${HOME}/.ptekwpdev"
CONFIG_FILE="${WORKSPACE}/workspaces.json"

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
source "$(dirname "$0")/lib/output.sh"

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
    "projects_dir": "~/projects",
    "assets_dir": "~/.ptekwpdev/assets",
    "certs_dir": "~/.ptekwpdev/certs",
    "db_image": "mariadb:10.11",
    "wp_image": "wordpress:6.7-php8.2"
  },
  "workspaces": {
    "example-site": {
      "domain": "example.dev",
      "db_name": "example_db",
      "db_user": "example_user",
      "plugins": ["akismet"],
      "theme": "twentytwentyfive",
      "secrets": {
        "db_pass_file": "~/.ptekwpdev/secrets/example-site.dev"
      }
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
  ensure_dir "$WORKSPACE/configs"
  ensure_dir "$WORKSPACE/secrets"

  # If config exists, read app-wide dirs
  if [[ -f "$CONFIG_FILE" ]]; then
    PROJECTS_DIR=$(jq -r '.app.projects_dir' "$CONFIG_FILE")
    ASSETS_DIR=$(jq -r '.app.assets_dir' "$CONFIG_FILE")
    CERTS_DIR=$(jq -r '.app.certs_dir' "$CONFIG_FILE")

    ensure_dir "$ASSETS_DIR"
    ensure_dir "$CERTS_DIR"
  fi
}

# === MAIN ===
info "Initializing PtekWPDev workspace..."

bootstrap_config
setup_directories

success "Setup complete. Workspace ready at ${WORKSPACE}"