#!/usr/bin/env bash
set -euo pipefail

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_BASE="${HOME}/.ptekwpdev"
CONFIG_FILE="${CONFIG_BASE}/environments.json"
TPL_FILE="${APP_BASE}/config/environments.tpl.json"
DOCKER_CONTEXT="${CONFIG_BASE}/docker"

# Must run from APP_BASE
if [[ "$PWD" != "$APP_BASE" ]]; then
  error "[ERR] Must run from APP_BASE: $APP_BASE"
  info "      Current directory: $PWD"
  exit 1
fi

mkdir -p "${CONFIG_BASE}"


# Source helpers
# Ensure app-wide logs directory exists
LOG_DIR="$APP_BASE/app/logs"
mkdir -p "${LOG_DIR}"
LOGFILE="$LOG_DIR/setup.log"
export LOGFILE
. "$APP_BASE/lib/output.sh"
log_header "Setup"


source "${APP_BASE}/lib/helpers.sh"


# Redirect stdout and stderr to log file (and console)
#exec > >(tee -a "$LOGFILE") 2>&1

# Ensure Docker is available
docker_check

info "Setup started, logging to $LOGFILE"


# Globals
WHATIF=false
ACTION=""

bootstrap_config() {
  if $WHATIF; then
    whatif "Would expand ${APP_BASE}/config/environments.tpl.json into ${CONFIG_FILE}"
    whatif "Ensuring app-level keys: build_home, project_base, docker_network, sqldb_root, sqldb_root_pass" >> "$LOGFILE"
    return 0
  fi

  info "Bootstrapping environments.json..."

  # If environments.json doesn't exist, create it from template
  if [[ ! -f "$CONFIG_FILE" ]]; then
    expand_env_file "$TPL_FILE" "$CONFIG_FILE"
    success "Config file created at $CONFIG_FILE"
  else
    warn "Config file already exists, creating backup before overwrite"
    backup_config "$CONFIG_FILE"
    expand_env_file "$TPL_FILE" "$CONFIG_FILE"
    success "Config file refreshed from template"
  fi

  # Ensure required app-level keys exist
  local required_keys=(build_home project_base network_name)
  for key in "${required_keys[@]}"; do
    if ! jq -e ".app.${key}" "$CONFIG_FILE" >/dev/null; then
      error "Missing required app-level key: $key"
      exit 1
    fi
  done
  local required_secrets=(sqldb_root sqldb_root_pass)
  for key in "${required_secrets[@]}"; do
    if ! jq -e ".app.secrets.${key}" "$CONFIG_FILE" >/dev/null; then
      error "Missing required app-level secret: $key"
      exit 1
    fi
  done

  success "Config file bootstrapped with all required app-level keys"
}

validate_config() {
  if $WHATIF; then
    whatif "Would validate JSON keys in $CONFIG_FILE"
    whatif "Required keys: build_home, project_base, sqldb_root, sqldb_root_pass" >> "$LOGFILE"
    return 0
  fi

  # Ensure JSON is valid
  if ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
    error "Invalid JSON in $CONFIG_FILE"
    exit 1
  fi

  # Required app-level keys
  local required_keys=(build_home project_base)
  for key in "${required_keys[@]}"; do
    if ! jq -e ".app.${key}" "$CONFIG_FILE" >/dev/null; then
      error "Missing required key in .app: $key"
      exit 1
    fi
  done
  local required_secrets=(sqldb_root sqldb_root_pass)
  for key in "${required_secrets[@]}"; do
    if ! jq -e ".app.secrets.${key}" "$CONFIG_FILE" >/dev/null; then
      error "Missing required app-level secret: $key"
      exit 1
    fi
  done

  success "Config file validated: all required app-level keys present"
}

setup_directories() {
  if $WHATIF; then
    whatif "Would ensure directories exist under $CONFIG_BASE"
    whatif "Would create: $CONFIG_BASE/config and $CONFIG_BASE/tmp" >> "$LOGFILE"
    return 0
  fi

  ensure_dir "$CONFIG_BASE/config"
  ensure_dir "$CONFIG_BASE/tmp"
}

deploy_docker_assets() {
  if $WHATIF; then
    whatif "Would deploy Docker assets to $DOCKER_CONTEXT"
    whatif "Would copy non-template assets from ${APP_BASE}/config/docker → $DOCKER_CONTEXT" >> "$LOGFILE"
    return 0
  fi

  info "Deploying Docker assets to $DOCKER_CONTEXT..."
  mkdir -p "$DOCKER_CONTEXT"

  # Copy only non-template assets
  find "${APP_BASE}/config/docker" -type f \
    ! -name '*.tpl*' \
    -exec cp {} "$DOCKER_CONTEXT/" \;

  success "Docker assets deployed to $DOCKER_CONTEXT"
}

generate_env_file() {
  local ENV_FILE="${DOCKER_CONTEXT}/.env"
  local TPL_FILE="${APP_BASE}/config/docker/env.app.tpl"

  if $WHATIF; then
    whatif "Would expand $TPL_FILE into $ENV_FILE using values from $CONFIG_FILE"
    return 0
  fi

  info "Generating app-level .env file for Docker context..."
  if [[ ! -f "$TPL_FILE" ]]; then
    error "Missing app env template: $TPL_FILE"
    exit 1
  fi

  # Start with a fresh file, don’t copy the template
  : > "$ENV_FILE"

  # Read template line by line and substitute
  while IFS= read -r line; do
    # Replace tokens with values from environments.json
    for key in $(jq -r '.app | keys[]' "$CONFIG_FILE"); do
      [[ "$key" == "secrets" ]] && continue
      val=$(jq -r ".app.${key}" "$CONFIG_FILE")
      safe_val=$(printf '%s\n' "$val" | sed 's/[&/\]/\\&/g')
      line=$(echo "$line" | sed "s|{{${key}}}|${safe_val}|g")
    done
    for key in $(jq -r '.app.secrets | keys[]' "$CONFIG_FILE"); do
      val=$(jq -r ".app.secrets.${key}" "$CONFIG_FILE")
      safe_val=$(printf '%s\n' "$val" | sed 's/[&/\]/\\&/g')
      line=$(echo "$line" | sed "s|{{${key}}}|${safe_val}|g")
    done
    echo "$line" >> "$ENV_FILE"
  done < "$TPL_FILE"

  success ".env file written directly to $ENV_FILE"
}

check_assets() {
  if $WHATIF; then
    whatif "Would check for assets volume"
    return 0
  fi

  if docker volume inspect ptekwpdev_assets_volume >/dev/null 2>&1; then
    info "Assets volume detected. Continuing with setup..."
  else
    error "Assets volume not found. Please run assets.sh init before setup.sh."
    exit 1
  fi
}

setup_containers() {
  if $WHATIF; then
    whatif "Would start core containers (sqldb, sqladmin)..."
    whatif "Would run: docker compose -f ${DOCKER_CONTEXT}/compose.setup.yml --env-file ${DOCKER_CONTEXT}/.env up -d sqldb sqladmin" >> "$LOGFILE"
    return 0
  fi

  info "Starting core containers (sqldb, sqladmin)..."
  run_or_preview "Bring up core containers" \
    docker compose -f "${DOCKER_CONTEXT}/compose.setup.yml" --env-file "${DOCKER_CONTEXT}/.env" up -d sqldb sqladmin

  for cname in ptekwpdev_db ptekwpdev_admin; do
    require_container_up "$cname" 20 3 || {
      error "Container $cname failed to start properly"
      exit 1
    }
    success "✅ $cname is running"
  done

  success "All core containers are online and ready."
}

teardown_containers() {
  if $WHATIF; then
    whatif "Would stop core containers..."
    whatif "Would run: docker compose -f ${DOCKER_CONTEXT}/compose.setup.yml --env-file ${DOCKER_CONTEXT}/.env down" >> "$LOGFILE"
    return 0
  fi

  run_or_preview "Stop containers" \
    docker compose -f "${DOCKER_CONTEXT}/compose.setup.yml" --env-file "${DOCKER_CONTEXT}/.env" down
}

reset_environment() {
  if $WHATIF; then
    whatif "Would reset environment (containers + volumes)..."
    whatif "Would run: docker compose -f ${DOCKER_CONTEXT}/compose.setup.yml --env-file ${DOCKER_CONTEXT}/.env down -v" >> "$LOGFILE"
    return 0
  fi

  run_or_preview "Tear down containers and volumes" \
    docker compose -f "${DOCKER_CONTEXT}/compose.setup.yml" --env-file "${DOCKER_CONTEXT}/.env" down -v
}

usage() {
  cat <<EOF
Usage: $(basename "$0") -a {init|up|down|reset} [-w|--what-if]

Options:
  -h, --help        Show this help message and exit
  -a, --action      Specify the action to perform:
                      init   → Initialize app-wide environment (network, sqldb, sqladmin)
                      up     → Start app-wide containers
                      down   → Stop app-wide containers
                      reset  → Tear down and re-initialize environment
  -w, --what-if     Dry-run mode: show what would be done without executing

Description:
  This script manages the app-wide WordPress development environment.
  It will:
    • Ensure app_base/logs/setup.log exists and capture all output
    • Verify Docker and Docker Compose availability
    • Create environments.json in config_base if missing (from environments.tpl.json)
    • Perform the specified action (-a) on app-wide resources

Examples:
  Initialize environment:
    ./setup.sh -a init

  Start containers:
    ./setup.sh -a up

  Stop containers:
    ./setup.sh -a down

  Reset environment:
    ./setup.sh -a reset

  Dry-run initialization:
    ./setup.sh -a init --what-if
EOF
}

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -w|--what-if)
      WHATIF=true
      shift
      ;;
    -a|--action)
      [[ $# -lt 2 ]] && { error "Missing value for $1"; usage; exit 1; }
      ACTION="$2"
      shift 2
      ;;
    *)
      error "Unknown option: $1"
      warn "Usage: $0 -a {init|up|down|reset} [-w|--what-if]"
      exit 1
      ;;
  esac
done

# Dispatcher
case "${ACTION:-}" in
  init|up)
    info "Initializing PtekWPDev workspace..."
    bootstrap_config
    validate_config
    setup_directories
    deploy_docker_assets
    generate_env_file
    success "Workspace ready at ${CONFIG_BASE}"
    check_assets
    setup_containers
    info "--- SUMMARY: ${ACTION} completed at $(date) ---" >> "$LOGFILE"
    info "Next step: provision a project with ./provision.sh -n <project>"
    ;;
  down)
    teardown_containers
    info "--- SUMMARY: down completed at $(date) ---" >> "$LOGFILE"
    ;;
  reset)
    reset_environment
    info "--- SUMMARY: reset completed at $(date) ---" >> "$LOGFILE"
    ;;
  *)
    error "Unknown or missing action: $ACTION"
    info "Usage: $0 -a {init|up|down|reset} [-w|--what-if]"
    exit 1
    ;;
esac

