#!/usr/bin/env bash
set -euo pipefail

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_BASE="${HOME}/.ptekwpdev"
CONFIG_FILE="${CONFIG_BASE}/environments.json"
TPL_FILE="${APP_BASE}/config/environments.tpl.json"
DOCKER_CONTEXT="${CONFIG_BASE}/docker"

# Must run from APP_BASE
if [[ "$PWD" != "$APP_BASE" ]]; then
  echo "[ERR] Must run from APP_BASE: $APP_BASE"
  echo "      Current directory: $PWD"
  exit 1
fi

mkdir -p "${CONFIG_BASE}"

# Source helpers and logging
LOG_DIR="$APP_BASE/app/logs"
mkdir -p "${LOG_DIR}"
LOGFILE="$LOG_DIR/deploy_app.log"
export LOGFILE
. "$APP_BASE/lib/output.sh"
log_header "Deploy App"

source "${APP_BASE}/lib/helpers.sh"

docker_check

info "Deploying app environment, logging to $LOGFILE"

WHAT_IF=false
ACTION=""

# ---------------------------------------------------------
# Bootstrap environments.json from template
# ---------------------------------------------------------
bootstrap_config() {
  if $WHAT_IF; then
    whatif "Would generate ${CONFIG_FILE} from ${TPL_FILE}"
    whatif "Would substitute app_base=${APP_BASE}"
    whatif "Would substitute project_base=${HOME}/projects/ptwpdev"
    whatif "Would insert preset demo project"
    return 0
  fi

  info "Bootstrapping environments.json..."

  if [[ -f "$CONFIG_FILE" ]]; then
    warn "Config file already exists, creating backup before overwrite"
    backup_config "$CONFIG_FILE"
  fi

  cp "$TPL_FILE" "$CONFIG_FILE"

  # App-level substitutions
  sed -i "s|{{app_base}}|$APP_BASE|g" "$CONFIG_FILE"
  sed -i "s|{{project_base}}|$HOME/projects/ptwpdev|g" "$CONFIG_FILE"

  # Preset demo project
  sed -i "s|__PROJECT_KEY__|demo|g" "$CONFIG_FILE"
  sed -i "s|{{project_name}}|demo|g" "$CONFIG_FILE"
  sed -i "s|{{project_title}}|Demo Project|g" "$CONFIG_FILE"
  sed -i "s|{{project_description}}|Preset demo WordPress environment|g" "$CONFIG_FILE"

  if ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
    error "Generated environments.json is invalid JSON"
    exit 1
  fi

  success "Config file created at $CONFIG_FILE"
}

# ---------------------------------------------------------
# Validate app-level config
# ---------------------------------------------------------
validate_config() {
  if $WHAT_IF; then
    whatif "Would validate JSON keys in $CONFIG_FILE"
    return 0
  fi

  if ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
    error "Invalid JSON in $CONFIG_FILE"
    exit 1
  fi

  local required_keys=(build_home project_base backend_network)
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

  success "Config file validated"
}

# ---------------------------------------------------------
# Deploy Docker engine templates → CONFIG_BASE/docker
# ---------------------------------------------------------
deploy_docker_templates() {
  local SRC="$APP_BASE/config/docker"
  local DST="$CONFIG_BASE/docker"
  ensure_dir "$DST"

  info "Deploying Docker engine templates to $DST"

  local assets=(
    "env.app.tpl"
    "env.project.tpl"
    "compose.app.yml"
    "compose.project.yml"
    "Dockerfile.wordpress"
    "Dockerfile.wpcli"
  )

  for file in "${assets[@]}"; do
    local src="$SRC/$file"
    local dst="$DST/$file"

    if [[ ! -f "$src" ]]; then
      warn "Missing docker template: $file"
      continue
    fi

    if $WHAT_IF; then
      whatif "Would copy $src → $dst"
    else
      cp "$src" "$dst"
      info "Copied $src → $dst"
    fi
  done

  success "Docker templates deployed"
}

# ---------------------------------------------------------
# Deploy proxy configs → CONFIG_BASE/config/proxy
# ---------------------------------------------------------
deploy_proxy_templates() {
  local SRC="$APP_BASE/config/proxy"
  local DST="$CONFIG_BASE/config/proxy"
  ensure_dir "$DST"

  info "Deploying proxy templates to $DST"

  local assets=(
    "nginx.conf.tpl"
  )

  for file in "${assets[@]}"; do
    local src="$SRC/$file"
    local dst="$DST/$file"

    if [[ ! -f "$src" ]]; then
      warn "Missing proxy template: $file"
      continue
    fi

    if $WHAT_IF; then
      whatif "Would copy $src → $dst"
    else
      cp "$src" "$dst"
      info "Copied $src → $dst"
    fi
  done

  success "Proxy templates deployed"
}

# ---------------------------------------------------------
# Deploy WordPress/PHP configs → CONFIG_BASE/config/wordpress
# ---------------------------------------------------------
deploy_wordpress_templates() {
  local SRC="$APP_BASE/config/wordpress"
  local DST="$CONFIG_BASE/config/wordpress"
  ensure_dir "$DST"

  info "Deploying WordPress/PHP templates to $DST"

  local assets=(
    "ptek-resources.ini"
  )

  for file in "${assets[@]}"; do
    local src="$SRC/$file"
    local dst="$DST/$file"

    if [[ ! -f "$src" ]]; then
      warn "Missing WordPress template: $file"
      continue
    fi

    if $WHAT_IF; then
      whatif "Would copy $src → $dst"
    else
      cp "$src" "$dst"
      info "Copied $src → $dst"
    fi
  done

  success "WordPress templates deployed"
}

# ---------------------------------------------------------
# Generate app-level .env
# ---------------------------------------------------------
generate_env_file() {
  local ENV_FILE="${DOCKER_CONTEXT}/.env"
  local TPL_FILE="${CONFIG_BASE}/docker/env.app.tpl"

  if $WHAT_IF; then
    whatif "Would expand $TPL_FILE → $ENV_FILE"
    return
  fi

  info "Generating app-level .env file..."

  : > "$ENV_FILE"

  while IFS= read -r line; do
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

  success ".env file written to $ENV_FILE"
}

# ---------------------------------------------------------
# Start core containers
# ---------------------------------------------------------
setup_containers() {
  if $WHAT_IF; then
    whatif "Would start core containers"
    return
  fi

  info "Starting core containers..."

  docker compose -f "${DOCKER_CONTEXT}/compose.app.yml" \
    --env-file "${DOCKER_CONTEXT}/.env" up -d sqldb sqladmin

  for cname in ptekwpdev_db ptekwpdev_admin; do
    require_container_up "$cname" 20 3 || {
      error "Container $cname failed to start"
      exit 1
    }
    success "$cname is running"
  done

  success "All core containers are online"
}

# ---------------------------------------------------------
# Parse flags
# ---------------------------------------------------------
usage() {
  echo "Usage: deploy_app.sh -a {init|up|down|reset} [-w]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -w|--what-if) WHAT_IF=true; shift ;;
    -a|--action) ACTION="$2"; shift 2 ;;
    *) error "Unknown option: $1"; exit 1 ;;
  esac
done

# ---------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------
case "${ACTION:-}" in
  init|up)
    bootstrap_config
    validate_config
    deploy_docker_templates
    deploy_proxy_templates
    deploy_wordpress_templates
    generate_env_file
    setup_containers
    success "App environment deployed at ${CONFIG_BASE}"
    ;;
  down)
    docker compose -f "${DOCKER_CONTEXT}/compose.app.yml" \
      --env-file "${DOCKER_CONTEXT}/.env" down
    ;;
  reset)
    docker compose -f "${DOCKER_CONTEXT}/compose.app.yml" \
      --env-file "${DOCKER_CONTEXT}/.env" down -v
    ;;
  *)
    error "Unknown or missing action: $ACTION"
    usage
    exit 1
    ;;
esac