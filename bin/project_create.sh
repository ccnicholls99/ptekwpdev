#!/usr/bin/env bash
# ====Summary>>=================================================================
# PTEKWPDEV — a multi-project, bootstrap app for localized WordPress development
# github: https://github.com/ccnicholls99/ptekwpdev.git
# ------------------------------------------------------------------------------
# Script: project_create.sh
#
# Synopsis:
#   Create a new project entry in CONFIG_BASE/config/projects.json using
#   flags or responsive prompts, generating secrets and validating fields.
#
# Description:
#   - Non-interactive by default (deterministic, CI-safe)
#   - Responsive mode (-r) enables interactive overrides
#   - Generates secrets using ptek_generate_secret()
#   - Builds a v2 project metadata block
#   - Writes metadata using project_add() from project_config.sh
#   - Supports WHAT-IF mode, auto-deploy, and auto-launch
#
# Notes:
#   - Pure metadata creation (no provisioning)
#   - No direct writes to projects.json (delegated to project_add)
#   - Compatible with project_config v2 schema
#
# ====<<Summary=================================================================

set -o errexit
set -o nounset
set -o pipefail

# ------------------------------------------------------------------------------
# Resolve APP_BASE (canonical pattern)
# ------------------------------------------------------------------------------
PTEK_APP_BASE="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"
export PTEK_APP_BASE

# ====Error Handling>>=====================================
_ts() { date +"%Y-%m-%d %H:%M:%S"; }
ptek_err() { COLOR_RED="\033[31m"; COLOR_RESET="\033[0m"; echo -e "${COLOR_RED}[$(_ts)] ERROR: $*${COLOR_RESET}" >&2; }

CALLER_PWD="$(pwd)"
trap 'ptek_err "Command failed (exit $?): $BASH_COMMAND"' ERR
trap 'cd "$CALLER_PWD" || true' EXIT
# ====<<Error Handling=====================================

# ====Log Handling>>=======================================
# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/output.sh"
# ====<<Log Handling=======================================

# ====App Config>>=========================================
# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/app_config.sh"
# ====<<App Config=========================================

# ====Helpers>>============================================
# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/helpers.sh"
# ====<<Helpers============================================


# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: project_create.sh [options]

Options:
  -p, --project <key>           Project key (lowercase, alphanumeric + _)
  --title <title>               Project title
  --description <text>          Project description
  -d, --domain <domain>         Domain name
  -n, --network <network>       Docker network name
  -b, --base-dir <dir>          Base directory under PROJECT_BASE
  --wp-image <image>            WordPress image
  --wp-host <host>              WordPress hostname
  --port <int>                  HTTP port
  --ssl-port <int>              HTTPS port

  --dev-plugin "name=... source=... type=local|remote init_git=true|false"
  --dev-theme  "name=... source=... type=local|remote init_git=true|false"

  -r, --responsive              Enable interactive prompts
  --auto_deploy                 Automatically deploy after creation
  --auto_launch                 Automatically launch after deploy
  -w, --what-if                 Dry run (no changes applied)
  -h, --help                    Show this help

Notes:
  - Non-interactive by default (deterministic)
  - Responsive mode allows overriding defaults interactively
  - Writes ONLY metadata; provisioning handled by project_deploy.sh
EOF
}

# ------------------------------------------------------------------------------
# State variables
# ------------------------------------------------------------------------------
RESPONSIVE=false
WHAT_IF=false
AUTO_DEPLOY=false
AUTO_LAUNCH=false

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
DEV_FLAGS=()

# ------------------------------------------------------------------------------
# Parse flags
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--responsive) RESPONSIVE=true; shift ;;
    -p|--project) PROJECT="$2"; shift 2 ;;
    --title) PROJECT_TITLE="$2"; shift 2 ;;
    --description) PROJECT_DESCRIPTION="$2"; shift 2 ;;
    -d|--domain) DOMAIN="$2"; shift 2 ;;
    -n|--network) NETWORK="$2"; shift 2 ;;
    -b|--base-dir) BASE_DIR="$2"; shift 2 ;;
    --wp-image) WP_IMAGE="$2"; shift 2 ;;
    --wp-host) WP_HOST="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --ssl-port) SSL_PORT="$2"; shift 2 ;;
    --dev-plugin|--dev-theme)
        DEV_FLAGS+=("$1" "$2")
        shift 2
        ;;
    --auto_deploy) AUTO_DEPLOY=true; shift ;;
    --auto_launch) AUTO_LAUNCH=true; shift ;;
    -w|--what-if) WHAT_IF=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# ------------------------------------------------------------------------------
# Validate project key
# ------------------------------------------------------------------------------
if [[ -z "$PROJECT" ]]; then
  error "Project key is required (--project)"
  exit 1
fi

if ! [[ "$PROJECT" =~ ^[a-z0-9_]+$ ]]; then
  error "Invalid project key: must be lowercase alphanumeric + underscores"
  exit 1
fi

# ====Project Config>>=====================================
# shellcheck source=/dev/null
source "${PTEK_APP_BASE}/lib/project_config.sh"
# ====<<Project Config=====================================

# ------------------------------------------------------------------------------
# Compute defaults (Option A)
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
DEFAULT_WP_CONTAINER="${PROJECT}_wp"
DEFAULT_WP_VOLUME="${PROJECT}_wp_vol"

PROJECT_TITLE="${PROJECT_TITLE:-$DEFAULT_TITLE}"
PROJECT_DESCRIPTION="${PROJECT_DESCRIPTION:-$DEFAULT_DESCRIPTION}"
DOMAIN="${DOMAIN:-$DEFAULT_DOMAIN}"
NETWORK="${NETWORK:-$DEFAULT_NETWORK}"
BASE_DIR="${BASE_DIR:-$DEFAULT_BASE_DIR}"
WP_IMAGE="${WP_IMAGE:-$DEFAULT_WP_IMAGE}"
WP_HOST="${WP_HOST:-$DEFAULT_WP_HOST}"
PORT="${PORT:-$DEFAULT_PORT}"
SSL_PORT="${SSL_PORT:-$DEFAULT_SSL_PORT}"
WP_CONTAINER="${WP_CONTAINER:-$DEFAULT_WP_CONTAINER}"
WP_VOLUME="${WP_VOLUME:-$DEFAULT_WP_VOLUME}"

# ------------------------------------------------------------------------------
# Responsive mode: show defaults and allow overrides
# ------------------------------------------------------------------------------
if [[ $RESPONSIVE == true ]]; then
  info "Defaults for project '${PROJECT}':"
  echo "  Title:     $PROJECT_TITLE"
  echo "  Desc:      $PROJECT_DESCRIPTION"
  echo "  Domain:    $DOMAIN"
  echo "  Network:   $NETWORK"
  echo "  Base dir:  $BASE_DIR"
  echo "  WP Image:  $WP_IMAGE"
  echo "  WP Host:   $WP_HOST"
  echo "  HTTP port: $PORT"
  echo "  HTTPS port:$SSL_PORT"
  echo "  WP Container Name:  $WP_CONTAINER"
  echo "  WP Volume Name:     $WP_VOLUME"
  echo

  read -rp "Change any of these? (y/n): " change
  if [[ "$change" =~ ^[Yy]$ ]]; then
    read -rp "Title [$PROJECT_TITLE]: " input; PROJECT_TITLE="${input:-$PROJECT_TITLE}"
    read -rp "Description [$PROJECT_DESCRIPTION]: " input; PROJECT_DESCRIPTION="${input:-$PROJECT_DESCRIPTION}"
    read -rp "Domain [$DOMAIN]: " input; DOMAIN="${input:-$DOMAIN}"
    read -rp "Network [$NETWORK]: " input; NETWORK="${input:-$NETWORK}"
    read -rp "Base dir [$BASE_DIR]: " input; BASE_DIR="${input:-$BASE_DIR}"
    read -rp "WordPress image [$WP_IMAGE]: " input; WP_IMAGE="${input:-$WP_IMAGE}"
    read -rp "WordPress host [$WP_HOST]: " input; WP_HOST="${input:-$WP_HOST}"
    read -rp "HTTP port [$PORT]: " input; PORT="${input:-$PORT}"
    read -rp "HTTPS port [$SSL_PORT]: " input; SSL_PORT="${input:-$SSL_PORT}"
    read -rp "WP Container [$WP_CONTAINER]: " input; WP_CONTAINER="${input:-$WP_CONTAINER}"
    read -rp "WP Volume [$WP_VOLUME]: " input; WP_VOLUME="${input:-$WP_VOLUME}"
  fi
elif [[ $WHAT_IF == true ]]; then
  whatif "Using defaults unless overridden by flags."
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
# Generate secrets (shared library)
# ------------------------------------------------------------------------------
SQLDB_NAME="${PROJECT}_db"
SQLDB_USER="${PROJECT}_user"
SQLDB_PASS="$( $WHAT_IF && echo '***secret***' || ptek_generate_secret )"

WP_ADMIN_USER="admin"
WP_ADMIN_EMAIL="admin@${DOMAIN}"
WP_ADMIN_PASS="$( $WHAT_IF && echo '***secret***' || ptek_generate_secret )"

# ------------------------------------------------------------------------------
# Build v2 project JSON block
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
  --arg wp_container "$WP_CONTAINER" \
  --arg wp_volume "$WP_VOLUME" \
  --arg dbname "$SQLDB_NAME" \
  --arg dbuser "$SQLDB_USER" \
  --arg dbpass "$SQLDB_PASS" \
  --arg wpuser "$WP_ADMIN_USER" \
  --arg wppass "$WP_ADMIN_PASS" \
  --arg wpemail "$WP_ADMIN_EMAIL" \
  '
  {
    project_title: $title,
    project_description: $desc,
    project_domain: $domain,
    project_network: $network,
    base_dir: $base_dir,

    wordpress: {
      image: $wpimage,
      host: $wphost,
      port: $port,
      ssl_port: $ssl_port,
      container_name: $wp_container,
      volume_name: $wp_volume,
      root_path: null,
      core_path: null,
      php_ini: null,
      wp_cli: null,
      dev_sources: {
        plugins: {},
        themes: {}
      }
    },

    secrets: {
      sqldb_name: $dbname,
      sqldb_user: $dbuser,
      sqldb_pass: $dbpass,
      wp_admin_user: $wpuser,
      wp_admin_pass: $wppass,
      wp_admin_email: $wpemail
    }
  }
')

# ------------------------------------------------------------------------------
# Insert project using project_add()
# ------------------------------------------------------------------------------
info "Adding project '${PROJECT}' to registry"

if [[ $WHAT_IF == true ]]; then
  whatif "Would call project_add '$PROJECT' with:"
  echo "$project_block"
else
  project_add "$PROJECT" "$project_block"
fi

# ------------------------------------------------------------------------------
# Dev sources
# ------------------------------------------------------------------------------
if [[ $RESPONSIVE == true ]]; then
  read -rp "Add dev sources now? (y/n): " add_dev
  if [[ "$add_dev" =~ ^[Yy]$ ]]; then
    if [[ $WHAT_IF == true ]]; then
      whatif "Would run project_dev_sources.sh --project ${PROJECT} ${DEV_FLAGS[*]}"
    else
      "${PTEK_APP_BASE}/bin/project_dev_sources.sh" --project "$PROJECT" "${DEV_FLAGS[@]}"
    fi
  fi
elif [[ ${#DEV_FLAGS[@]} -gt 0 ]]; then
  info "Forwarding dev-source flags"
  if [[ $WHAT_IF == true ]]; then
    whatif "Would run project_dev_sources.sh --project ${PROJECT} ${DEV_FLAGS[*]}"
  else
    "${PTEK_APP_BASE}/bin/project_dev_sources.sh" --project "$PROJECT" "${DEV_FLAGS[@]}"
  fi
fi

# ------------------------------------------------------------------------------
# Deployment
# ------------------------------------------------------------------------------
PROJECT_DEPLOYED=false

if [[ $RESPONSIVE == true && $AUTO_DEPLOY == false ]]; then
  read -rp "Deploy now? (y/n): " deploy_now
  if [[ "$deploy_now" =~ ^[Yy]$ ]]; then
    if [[ $WHAT_IF == true ]]; then
      whatif "Would deploy project"
    else
      "${PTEK_APP_BASE}/bin/project_deploy.sh" --project "$PROJECT" --action deploy
      PROJECT_DEPLOYED=true
    fi
  fi
elif [[ $AUTO_DEPLOY == true ]]; then
  if [[ $WHAT_IF == true ]]; then
    whatif "Would deploy project"
  else
    "${PTEK_APP_BASE}/bin/project_deploy.sh" --project "$PROJECT" --action deploy
    PROJECT_DEPLOYED=true
  fi
fi

# ------------------------------------------------------------------------------
# Launch
# ------------------------------------------------------------------------------
if [[ $RESPONSIVE == true && $PROJECT_DEPLOYED == true && $AUTO_LAUNCH == false ]]; then
  read -rp "Launch now? (y/n): " launch_now
  if [[ "$launch_now" =~ ^[Yy]$ ]]; then
    if [[ $WHAT_IF == true ]]; then
      whatif "Would launch project"
    else
      "${PTEK_APP_BASE}/bin/project_launch.sh" --project "$PROJECT" --action deploy
    fi
  fi
elif [[ $AUTO_LAUNCH == true && $PROJECT_DEPLOYED == true ]]; then
  if [[ $WHAT_IF == true ]]; then
    whatif "Would launch project"
  else
    "${PTEK_APP_BASE}/bin/project_launch.sh" --project "$PROJECT" --action deploy
  fi
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
success "Project creation complete"

echo
echo "Project:   $PROJECT"
echo "Title:     $PROJECT_TITLE"
echo "Domain:    $DOMAIN"
echo "Network:   $NETWORK"
echo "Base dir:  $BASE_DIR"
echo "WP Image:  $WP_IMAGE"
echo "Ports:     $PORT / $SSL_PORT"
echo "Container: $WP_CONTAINER"
echo "Volume:    $WP_VOLUME"
echo "Auto Deploy: $AUTO_DEPLOY"
echo "Auto Launch: $AUTO_LAUNCH"
echo

exit 0