#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — Project Creation Script (v2)
#  Script: project_create.sh
#
#  Synopsis:
#    Create a new project entry in CONFIG_BASE/config/projects.json using
#    hybrid input (flags override, defaults shown, user may override).
#    Generates secrets, validates fields, and optionally triggers deployment.
#
#  Notes:
#    - Pure metadata creation (no provisioning)
#    - Writes ONLY to CONFIG_BASE/config/projects.json
#    - WHAT-IF safe
#    - TODO: Add JSON schema validation once schema is finalized
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail

#
# usage():
# Print command options
#
usage() {
  cat <<EOF
Usage: project_create.sh [options]

Options:
  -p, --project <key>           Project key (lowercase, alphanumeric + _)
  -d, --domain <domain>         Project domain
  -n, --network <network>       Docker network name
  -b, --base-dir <dir>          Base directory under PROJECT_BASE
  --port <int>                  WordPress HTTP port
  --ssl-port <int>              WordPress HTTPS port

  --dev-plugin "name=... source=... type=local|remote init_git=true|false"
  --dev-theme  "name=... source=... type=local|remote init_git=true|false"

  -w, --what-if                 Dry run (no changes applied)
  -h, --help                    Show this help

Notes:
  - Defaults are auto-generated and shown before confirmation.
  - User may override defaults interactively.
  - This script ONLY writes metadata to projects.json.
  - Provisioning is handled by project_deploy.sh.
EOF
}

print_summary() {
  echo
  echo "Published to $PROJECTS_FILE..."
  echo "  Project:   $PROJECT"
  echo "  Title:     $PROJECT_TITLE"
  echo "  Desc:      $PROJECT_DESCRIPTION"
  echo "  Domain:    $DOMAIN"
  echo "  Network:   $NETWORK"
  echo "  Base dir:  $BASE_DIR"
  echo "  WP Image:  $WP_IMAGE"
  echo "  WP Host:   $WP_HOST"
  echo "  Ports:     $PORT / $SSL_PORT"
  echo "  SQLDB:     $SQLDB_NAME"
  echo "  DB User:   $SQLDB_USER"
  echo "  WP User:   $WP_ADMIN_USER"
  echo "  Dev flags: ${#DEV_FLAGS[@]}"
  echo
  echo "Next steps:"
  echo "  project_deploy.sh --project ${PROJECT} --action deploy"
  echo
}


# ------------------------------------------------------------------------------
# Preserve caller directory
# ------------------------------------------------------------------------------
CALLER_PWD="$(pwd)"
cleanup() { cd "$CALLER_PWD" || true; }
trap cleanup EXIT

# ------------------------------------------------------------------------------
# Resolve APP_BASE and load libraries
# ------------------------------------------------------------------------------
PTEK_APP_BASE="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"
export PTEK_APP_BASE

CHECK_FILE="${PTEK_APP_BASE}/lib/app_config.sh"
# shellcheck source=/dev/null
if [[ -f $CHECK_FILE ]]; then
  source "$CHECK_FILE"
else
  printf "ERROR: Cannot locate app_config library at %s\n" "$CHECK_FILE"
  exit 1
fi
CHECK_FILE="${PTEK_APP_BASE}/lib/helpers.sh"
# shellcheck source=/dev/null
if [[ -f $CHECK_FILE ]]; then
  source "$CHECK_FILE"
else
  printf "ERROR: Cannot locate helpers library at %s\n" "$CHECK_FILE"
  exit 1
fi
CHECK_FILE=""

set_log --truncate "$(appcfg app_log_dir)/project_create.log" \
  "=== Project Create Run ($(date)) ==="

CONFIG_BASE=
PROJECTS_FILE=
PROJECT=""
PROJECT_TITLE=""
PROJECT_DESCRIPTION=""
DOMAIN=""
NETWORK=""
BASE_DIR=""
WP_IMAGE=""
WP_HOST=""
PORT=""
SSL_PORT=""
# 0 to enable, any non-zero value to disable
WHAT_IF=1     
DEV_FLAGS=()

# ------------------------------------------------------------------------------
# Parse flags
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project) PROJECT="$2"; shift 2 ;;
    --title) PROJECT_TITLE="$2"; shift 2 ;;
    --description) PROJECT_DESCRIPTION="$2"; shift 2 ;;
    --wp-image) WP_IMAGE="$2"; shift 2 ;;
    --wp-host) WP_HOST="$2"; shift 2 ;;
    -d|--domain) DOMAIN="$2"; shift 2 ;;
    -n|--network) NETWORK="$2"; shift 2 ;;
    -b|--base-dir) BASE_DIR="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --ssl-port) SSL_PORT="$2"; shift 2 ;;
    --dev-plugin|--dev-theme)
        DEV_FLAGS+=("$1" "$2")
        shift 2
        ;;
    -w|--what-if) WHAT_IF=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# ------------------------------------------------------------------------------
# Resolve CONFIG_BASE
# ------------------------------------------------------------------------------
CONFIG_BASE="$(appcfg config_base)"
PROJECTS_FILE="${CONFIG_BASE}/config/projects.json"

# Ensure projects.json exists
if [[ ! -f "$PROJECTS_FILE" ]]; then
  if [[ $WHAT_IF -eq 0 ]]; then
    whatif "projects.json not found. Would create $PROJECTS_FILE"
  else
    info "projects.json missing — creating new registry"
    mkdir -p "$(dirname "$PROJECTS_FILE")"
    echo '{ "projects": {} }' > "$PROJECTS_FILE"
  fi
  success "Created new projects.json"
elif [[ $WHAT_IF -eq 0 ]]; then
  whatif "$PROJECTS_FILE exists. Would add new project config"
fi

# ------------------------------------------------------------------------------
# Require project key
# ------------------------------------------------------------------------------
if [[ -z "$PROJECT" ]]; then
  error "Project key is required (--project)"
  exit 1
fi

if ! [[ "$PROJECT" =~ ^[a-z0-9_]+$ ]]; then
  error "Invalid project key: must be lowercase alphanumeric + underscores"
  exit 1
fi

# ------------------------------------------------------------------------------
# Check if project already exists
# ------------------------------------------------------------------------------
if jq -e ".projects.\"${PROJECT}\"" "$PROJECTS_FILE" >/dev/null; then
  error "Project '${PROJECT}' already exists in projects.json"
  exit 1
fi

# ------------------------------------------------------------------------------
# Compute defaults
# ------------------------------------------------------------------------------
DEFAULT_DOMAIN="${PROJECT}.local"
DEFAULT_TITLE="${PROJECT}"
DEFAULT_DESCRIPTION="A new WordPress site for ${PROJECT}"
DEFAULT_NETWORK="$(appcfg app_key)_${PROJECT}_net"
DEFAULT_BASE_DIR="${PROJECT}"
DEFAULT_WP_IMAGE="$(appcfg wordpress_defaults.image)"
DEFAULT_WP_HOST="${PROJECT}.local"
DEFAULT_PORT="$(appcfg wordpress_defaults.port)"
DEFAULT_SSL_PORT="$(appcfg wordpress_defaults.ssl_port)"

# Apply defaults if missing
PROJECT_TITLE="${PROJECT_TITLE:-$DEFAULT_TITLE}"
PROJECT_DESCRIPTION="${PROJECT_DESCRIPTION:-$DEFAULT_DESCRIPTION}"
DOMAIN="${DOMAIN:-$DEFAULT_DOMAIN}"
NETWORK="${NETWORK:-$DEFAULT_NETWORK}"
BASE_DIR="${BASE_DIR:-$DEFAULT_BASE_DIR}"
WP_IMAGE="${WP_IMAGE:-$DEFAULT_WP_IMAGE}"
WP_HOST="${WP_HOST:-$DEFAULT_WP_HOST}"
PORT="${PORT:-$DEFAULT_PORT}"
SSL_PORT="${SSL_PORT:-$DEFAULT_SSL_PORT}"

# ------------------------------------------------------------------------------
# Show defaults and ask if user wants to override
# ------------------------------------------------------------------------------
if [[ $WHAT_IF -ne 0 ]]; then
  info "Using defaults for project '${PROJECT}':"
  echo "  Title:     $PROJECT_TITLE"
  echo "  Desc:      $PROJECT_DESCRIPTION"
  echo "  Domain:    $DOMAIN"
  echo "  Network:   $NETWORK"
  echo "  Base dir:  $BASE_DIR"
  echo "  WP Image:  $WP_IMAGE"
  echo "  WP Host:   $WP_HOST"  
  echo "  HTTP port: $PORT"
  echo "  HTTPS port:$SSL_PORT"
  echo

  read -rp "Would you like to change any of these? (y/n): " change_defaults
  if [[ "$change_defaults" =~ ^[Yy]$ ]]; then
    read -rp "Title [$PROJECT_TITLE]: " input; PROJECT_TITLE="${input:-$PROJECT_TITLE}"
    read -rp "Description [$PROJECT_DESCRIPTION]: " input; PROJECT_DESCRIPTION="${input:-$PROJECT_DESCRIPTION}"
    read -rp "Domain [$DOMAIN]: " input; DOMAIN="${input:-$DOMAIN}"
    read -rp "Network [$NETWORK]: " input; NETWORK="${input:-$NETWORK}"
    read -rp "Base dir [$BASE_DIR]: " input; BASE_DIR="${input:-$BASE_DIR}"
    read -rp "WordPress image [$WP_IMAGE]: " input; WP_IMAGE="${input:-$WP_IMAGE}"
    read -rp "WordPress host [$WP_HOST]: " input; WP_HOST="${input:-$WP_HOST}"
    read -rp "HTTP port [$PORT]: " input; PORT="${input:-$PORT}"
    read -rp "HTTPS port [$SSL_PORT]: " input; SSL_PORT="${input:-$SSL_PORT}"
  fi
else
  whatif "Would use defaults unless overridden by flags."
fi

# ------------------------------------------------------------------------------
# Validate ports
# ------------------------------------------------------------------------------
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
  error "Invalid port: $PORT"
  exit 1
fi

if ! [[ "$SSL_PORT" =~ ^[0-9]+$ ]] || (( SSL_PORT < 1 || SSL_PORT > 65535 )); then
  error "Invalid SSL port: $SSL_PORT"
  exit 1
fi

# ------------------------------------------------------------------------------
# Generate secrets
# ------------------------------------------------------------------------------
generate_secret() {
  head -c 32 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 16
}

SQLDB_NAME="${PROJECT}_db"
SQLDB_USER="${PROJECT}_user"
if [[ $WHAT_IF -eq 0 ]]; then
  SQLDB_PASS="***secret***"
else
  SQLDB_PASS="$(generate_secret)"
fi

WP_ADMIN_USER="admin"
WP_ADMIN_EMAIL="admin@${DOMAIN}"
if [[ $WHAT_IF -eq 0 ]]; then
  WP_ADMIN_PASS="***secret***"
else
  WP_ADMIN_PASS="$(generate_secret)"
fi 

# ------------------------------------------------------------------------------
# Build JSON block
# ------------------------------------------------------------------------------
project_block=$(jq -n \
  --arg title "$PROJECT_TITLE" \
  --arg desc "$PROJECT_DESCRIPTION" \
  --arg domain "$DOMAIN" \
  --arg network "$NETWORK" \
  --arg base_dir "$BASE_DIR" \
  --arg wpimage "$WP_IMAGE" \
  --arg wphost "$WP_HOST" \
  --arg port "$PORT" \
  --arg ssl_port "$SSL_PORT" \
  --arg dbname "$SQLDB_NAME" \
  --arg dbuser "$SQLDB_USER" \
  --arg dbpass "$SQLDB_PASS" \
  --arg wpuser "$WP_ADMIN_USER" \
  --arg wppass "$WP_ADMIN_PASS" \
  --arg wpemail "$WP_ADMIN_EMAIL" \
  '{
    project_title: $title,
    project_description: $desc,
    project_domain: $domain,
    project_network: $network,
    base_dir: $base_dir,
    wordpress: {
      image: $wpimage,
      host: $wphost,
      port: $port,
      ssl_port: $ssl_port
    },
    secrets: {
      sqldb_name: $dbname,
      sqldb_user: $dbuser,
      sqldb_pass: $dbpass,
      wp_admin_user: $wpuser,
      wp_admin_pass: $wppass,
      wp_admin_email: $wpemail
    },
    dev_sources: {
      plugins: {},
      themes: {}
    }
  }'
)

# ------------------------------------------------------------------------------
# Insert into projects.json
# ------------------------------------------------------------------------------
info "Adding project '${PROJECT}' to projects.json"

if [[ $WHAT_IF -eq 0 ]]; then
  whatif "Would insert project block into ${PROJECTS_FILE}"
  echo "$project_block"
else
  tmpfile=$(mktemp)
  jq ".projects.\"${PROJECT}\" = ${project_block}" "$PROJECTS_FILE" > "$tmpfile"
  mv "$tmpfile" "$PROJECTS_FILE"
  success "Project '${PROJECT}' added to projects.json"
fi

# ------------------------------------------------------------------------------
# Optional: Add dev sources
# ------------------------------------------------------------------------------
if [[ ${#DEV_FLAGS[@]} -gt 0 ]]; then
  info "Forwarding dev-source flags to project_dev_sources.sh"
  if [[ $WHAT_IF -eq 0 ]]; then
    whatif "Would run project_dev_sources.sh --project ${PROJECT} ${DEV_FLAGS[*]}"
  else
    "${PTEK_APP_BASE}/bin/project_dev_sources.sh" --project "${PROJECT}" "${DEV_FLAGS[@]}"
  fi
else
  if [[ $WHAT_IF -ne 0 ]]; then
    read -rp "Add dev sources now? (y/n): " add_dev
    if [[ "$add_dev" =~ ^[Yy]$ ]]; then
      "${PTEK_APP_BASE}/bin/project_dev_sources.sh" --project "${PROJECT}" --interactive
    fi
  fi
fi

# ------------------------------------------------------------------------------
# Optional: Deploy now
# ------------------------------------------------------------------------------
if [[ $WHAT_IF -ne 0 ]]; then
  read -rp "Deploy project now? (y/n): " deploy_now
  if [[ "$deploy_now" =~ ^[Yy]$ ]]; then
    "${PTEK_APP_BASE}/bin/project_deploy.sh" --project "${PROJECT}" --action deploy
  fi
else
  whatif "Would run project_deploy.sh --project ${PROJECT} --action deploy"
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
success "Project creation complete"

print_summary

exit 0