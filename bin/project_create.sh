#!/usr/bin/env bash
# ==============================================================================
#  PTEKWPDEV — Project Creation Script
#  Script: project_create.sh
#
#  Synopsis:
#    Create a new project entry in CONFIG_BASE/config/projects.json using
#    hybrid input (flags override, missing values prompt). Generates secrets,
#    validates all fields, and optionally triggers project_deploy.sh.
#
#  Notes:
#    - Pure metadata creation (no provisioning)
#    - Writes ONLY to CONFIG_BASE/config/projects.json
#    - WHAT-IF safe
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail

# ------------------------------------------------------------------------------
# Preserve caller directory
# ------------------------------------------------------------------------------

CALLER_PWD="$(pwd)"
cleanup() { cd "$CALLER_PWD" || true; }
trap cleanup EXIT

# ------------------------------------------------------------------------------
# Resolve APP_BASE and load libraries
# ------------------------------------------------------------------------------

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "${APP_BASE}/lib/output.sh"
source "${APP_BASE}/lib/helpers.sh"
source "${APP_BASE}/lib/app_config.sh"

set_log --truncate "$(appcfg app_log_dir)/project_create.log" \
  "=== Project Create Run ($(date)) ==="

# ------------------------------------------------------------------------------
# Resolve CONFIG_BASE
# ------------------------------------------------------------------------------

CONFIG_BASE="$(appcfg config_base)"
PROJECTS_FILE="${CONFIG_BASE}/config/projects.json"

if [[ ! -f "$PROJECTS_FILE" ]]; then
  error "Missing projects.json at ${PROJECTS_FILE}"
  exit 1
fi

# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------

PROJECT=""
DOMAIN=""
NETWORK=""
BASE_DIR=""
PORT=""
SSL_PORT=""
WHAT_IF=false
FORWARDED_DEV_FLAGS=()

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------

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

  --dev-plugin name=... source=... type=local|remote init_git=true|false
  --dev-theme  name=... source=... type=local|remote init_git=true|false

  -w, --what-if                 Dry run (no changes applied)
  -h, --help                    Show this help

Notes:
  - Missing values will be prompted interactively.
  - This script ONLY writes metadata to projects.json.
  - Provisioning is handled by project_deploy.sh.
EOF
}

# ------------------------------------------------------------------------------
# Parse flags
# ------------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project) PROJECT="$2"; shift 2 ;;
    -d|--domain) DOMAIN="$2"; shift 2 ;;
    -n|--network) NETWORK="$2"; shift 2 ;;
    -b|--base-dir) BASE_DIR="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --ssl-port) SSL_PORT="$2"; shift 2 ;;
    --dev-plugin)
        FORWARDED_DEV_FLAGS+=(--add-plugin "$2")
        shift 2
        ;;
    --dev-theme)
        FORWARDED_DEV_FLAGS+=(--add-theme "$2")
        shift 2
        ;;
    -w|--what-if) WHAT_IF=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# ------------------------------------------------------------------------------
# Interactive prompts for missing values
# ------------------------------------------------------------------------------

prompt_if_empty() {
  local var_name="$1"
  local prompt="$2"
  local default="${3:-}"

  local current_val="${!var_name}"

  if [[ -z "$current_val" ]]; then
    if [[ -n "$default" ]]; then
      read -rp "$prompt [$default]: " input
      input="${input:-$default}"
    else
      read -rp "$prompt: " input
    fi
    printf -v "$var_name" "%s" "$input"
  fi
}

prompt_if_empty PROJECT "Enter project key"
prompt_if_empty DOMAIN "Enter project domain"
prompt_if_empty NETWORK "Enter project network"
prompt_if_empty BASE_DIR "Enter base directory under PROJECT_BASE"
prompt_if_empty PORT "Enter WordPress HTTP port" "8080"
prompt_if_empty SSL_PORT "Enter WordPress HTTPS port" "8443"

# ------------------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------------------

if ! [[ "$PROJECT" =~ ^[a-z0-9_]+$ ]]; then
  error "Invalid project key: must be lowercase alphanumeric + underscores"
  exit 1
fi

if jq -e ".projects.\"${PROJECT}\"" "$PROJECTS_FILE" >/dev/null; then
  error "Project '${PROJECT}' already exists in projects.json"
  exit 1
fi

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

generate_secret() { tr -dc A-Za-z0-9 </dev/urandom | head -c 16; }

SQLDB_NAME="${PROJECT}_db"
SQLDB_USER="${PROJECT}_user"
SQLDB_PASS="$(generate_secret)"

WP_ADMIN_USER="admin"
WP_ADMIN_PASS="$(generate_secret)"
WP_ADMIN_EMAIL="admin@${DOMAIN}"

# ------------------------------------------------------------------------------
# Build JSON block
# ------------------------------------------------------------------------------

project_block=$(jq -n \
  --arg domain "$DOMAIN" \
  --arg network "$NETWORK" \
  --arg base_dir "$BASE_DIR" \
  --arg port "$PORT" \
  --arg ssl_port "$SSL_PORT" \
  --arg dbname "$SQLDB_NAME" \
  --arg dbuser "$SQLDB_USER" \
  --arg dbpass "$SQLDB_PASS" \
  --arg wpuser "$WP_ADMIN_USER" \
  --arg wppass "$WP_ADMIN_PASS" \
  --arg wpemail "$WP_ADMIN_EMAIL" \
  '{
    project_domain: $domain,
    project_network: $network,
    base_dir: $base_dir,
    wordpress: {
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

if $WHAT_IF; then
  whatif "Would insert project block into ${PROJECTS_FILE}"
  echo "$project_block"
else
  tmpfile=$(mktemp)
  jq ".projects.\"${PROJECT}\" = ${project_block}" "$PROJECTS_FILE" > "$tmpfile"
  mv "$tmpfile" "$PROJECTS_FILE"
  success "Project '${PROJECT}' added to projects.json"
fi

# ------------------------------------------------------------------------------
# Ask to add dev sources now
# ------------------------------------------------------------------------------
read -rp "Add dev sources now? (y/n): " add_dev
if [[ ${#FORWARDED_DEV_FLAGS[@]} -gt 0 ]]; then
  info "Forwarding dev source flags to project_dev_sources.sh"

  if $WHAT_IF; then
    whatif "Would run project_dev_sources.sh --project ${PROJECT} ${FORWARDED_DEV_FLAGS[*]}"
  else
    "${APP_BASE}/bin/project_dev_sources.sh" --project "${PROJECT}" "${FORWARDED_DEV_FLAGS[@]}"
  fi
else
  read -rp "Add dev sources now? (y/n): " add_dev
  if [[ "$add_dev" =~ ^[Yy]$ ]]; then
    if $WHAT_IF; then
      whatif "Would run project_dev_sources.sh --project ${PROJECT} --interactive"
    else
      "${APP_BASE}/bin/project_dev_sources.sh" --project "${PROJECT}" --interactive
    fi
  fi
fi

# ------------------------------------------------------------------------------
# Ask to deploy now
# ------------------------------------------------------------------------------

read -rp "Deploy project now? (y/n): " deploy_now
if [[ "$deploy_now" =~ ^[Yy]$ ]]; then
  if $WHAT_IF; then
    whatif "Would run project_deploy.sh --project ${PROJECT} --action deploy"
  else
    "${APP_BASE}/bin/project_deploy.sh" --project "${PROJECT}" --action deploy
  fi
fi

success "Project creation complete"
exit 0