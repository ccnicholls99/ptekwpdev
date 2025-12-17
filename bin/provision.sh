#!/usr/bin/env bash
#
# Provision script for WordPress dev environments (ptekwpdev)
#

set -euo pipefail

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT=""
CONFIG_BASE="$HOME/.ptekwpdev"
CONFIG_FILE="$CONFIG_BASE/environments.json"
WHATIF=false
ACTION=""

# Load helpers
source "$APP_BASE/lib/output.sh"
source "$APP_BASE/lib/helpers.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") -p NAME -a {init|up|down|reset} [-w|--what-if]

Options:
  -p, --project NAME   REQUIRED project key
  -a, --action ACTION  REQUIRED action:
                         init   → Initialize project (.env, compose.project.yml)
                         up     → Start project containers
                         down   → Stop project containers
                         reset  → Tear down and re-initialize project
  -w, --what-if        Dry-run mode: show what would be done without executing
  -h, --help           Show this help message

Example:
  $(basename "$0") --project demo --action init
EOF
}

parse_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--project)
        if [[ $# -lt 2 ]]; then
          error "Missing value for $1"
          usage
          exit 1
        fi
        PROJECT="$2"
        shift 2
        ;;
      -a|--action)
        if [[ $# -lt 2 ]]; then
          error "Missing value for $1"
          usage
          exit 1
        fi
        ACTION="$2"
        shift 2
        ;;
      -w|--what-if)
        WHATIF=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done

  if [[ -z "$PROJECT" ]]; then
    error "--project is required"
    usage
    exit 1
  fi

  if [[ -z "$ACTION" ]]; then
    error "--action is required"
    usage
    exit 1
  fi
}

resolve_project() {
  [[ ! -f "$CONFIG_FILE" ]] && { error "No project config at $CONFIG_FILE"; exit 1; }

  APP_PROJECT_BASE=$(jq -r '.app.project_base' "$CONFIG_FILE" | sed "s|\$HOME|$HOME|")
  PROJECT_CONFIG=$(jq -r --arg pr "$PROJECT" '.environments[$pr]' "$CONFIG_FILE")

  HOST_DOMAIN=$(echo "$PROJECT_CONFIG" | jq -r '.project_domain // empty')
  BASE_DIR_REL=$(echo "$PROJECT_CONFIG" | jq -r '.base_dir // empty' | sed 's|^/||')
  PROJECT_BASE="$APP_PROJECT_BASE/$BASE_DIR_REL"

  [[ -z "$BASE_DIR_REL" || -z "$HOST_DOMAIN" ]] && { error "Project '$PROJECT' missing base_dir or project_domain"; exit 1; }

  LOG_DIR="$PROJECT_BASE/app/logs"
  ensure_dir "$LOG_DIR"
  LOGFILE="$LOG_DIR/provision.log"
  export LOGFILE
  log_header "Provision: $PROJECT"
  #exec > >(tee -a "$LOGFILE") 2>&1

  info "Resolved project: $PROJECT_BASE (domain=$HOST_DOMAIN)"
}

scaffold_directories() {
  if $WHATIF; then
    whatif "Would scaffold under $PROJECT_BASE: app, bin, docker, src, app/config/docker, app/config/nginx"
  else
    ensure_dir "$PROJECT_BASE"
    for dir in app bin config docker src; do ensure_dir "$PROJECT_BASE/$dir"; done
    ensure_dir "$PROJECT_BASE/config/proxy"
    ensure_dir "$PROJECT_BASE/config/wordpress"
    success "Scaffold created under $PROJECT_BASE"
  fi
}

generate_env_file() {
  ENV_FILE="$PROJECT_BASE/docker/.env"
  TPL_ENV="$APP_BASE/config/docker/env.project.tpl"
  ensure_dir "$(dirname "$ENV_FILE")"

  if $WHATIF; then
    whatif "Would generate .env from $TPL_ENV → $ENV_FILE"
    return
  fi

  cp "$TPL_ENV" "$ENV_FILE"
  project_json=$(jq -r --arg pr "$PROJECT" '.environments[$pr]' "$CONFIG_FILE")

  for key in $(echo "$project_json" | jq -r 'keys[]'); do
    [[ "$key" == "secrets" ]] && continue
    val=$(echo "$project_json" | jq -r ".${key}")
    safe_val=$(printf '%s\n' "$val" | sed 's/[&/\]/\\&/g')
    sed -i "s|{{${key}}}|${safe_val}|g" "$ENV_FILE"
  done

  secrets_json=$(echo "$project_json" | jq -r '.secrets // empty')
  if [[ -n "$secrets_json" && "$secrets_json" != "null" ]]; then
    for key in $(echo "$secrets_json" | jq -r 'keys[]'); do
      val=$(echo "$secrets_json" | jq -r ".${key}")
      safe_val=$(printf '%s\n' "$val" | sed 's/[&/\]/\\&/g')
      info "Replacing {{${key}}} with [*****]"
      sed -i "s|{{${key}}}|${safe_val}|g" "$ENV_FILE"
    done
  fi

  log_env_expansion "$project_json" "$ENV_FILE"
  success ".env file generated for $PROJECT"
}

# Patch FROM line in Dockerfile.wordpress
# Do not call directly; use copy_if_newer with this as callback
# Patch only the FROM line that references the wordpress image tag
patch_wordpress_from_cb() {
  awk -v img="$WORDPRESS_IMAGE" '
    /^FROM[[:space:]]+wordpress:/ {
      print "FROM wordpress:" img " AS wpbuild"
      next
    }
    { print }
  ' "$1"
}

deploy_docker_assets() {
  # Project-local Docker ignore file
  DOCKERIGNORE_SRC="$APP_BASE/config/docker/.dockerignore.project"
  DOCKERIGNORE_DST="$PROJECT_BASE/docker/.dockerignore"

  if [[ -f "$DOCKERIGNORE_SRC" ]]; then
    if [[ "$WHATIF" == true ]]; then
      whatif "Would copy project Docker ignore file from $DOCKERIGNORE_SRC → $DOCKERIGNORE_DST"
    else
      cp "$DOCKERIGNORE_SRC" "$DOCKERIGNORE_DST"
      info "Copied project Docker ignore file from $DOCKERIGNORE_SRC → $DOCKERIGNORE_DST"
    fi
  fi

  # WordPress Dockerfile, replace image and version, then deploy to project
  # WordPress Dockerfile (patched with correct image version)
  DOCKER_SRC="$APP_BASE/config/docker/Dockerfile.wordpress"
  DOCKER_DST="$PROJECT_BASE/docker/Dockerfile.wordpress"
  WORDPRESS_IMAGE=$(echo "$PROJECT_CONFIG" | jq -r '.wordpress_image // "php8.1"')

  copy_if_newer "$APP_BASE/config/docker/Dockerfile.wordpress" \
              "$PROJECT_BASE/docker/Dockerfile.wordpress" \
              "Dockerfile.wordpress" \
              patch_wordpress_from_cb

  # Sanity check: confirm FROM line in target Dockerfile
  if [[ -f "$PROJECT_BASE/docker/Dockerfile.wordpress" ]]; then
    local from_line
    from_line="$(head -1 "$PROJECT_BASE/docker/Dockerfile.wordpress")"
    info "Sanity check: Dockerfile.wordpress FROM line → ${from_line}"
  fi

  # WP-CLI Dockerfile
  WPCLI_SRC="$APP_BASE/docker/Dockerfile.wpcli"
  WPCLI_DST="$PROJECT_BASE/docker/Dockerfile.wpcli"

  if [[ -f "$WPCLI_SRC" ]]; then
    if [[ "$WHATIF" == true ]]; then
      whatif "Would copy WP-CLI Dockerfile from $WPCLI_SRC → $WPCLI_DST"
    else
      cp "$WPCLI_SRC" "$WPCLI_DST"
      info "Copied WP-CLI Dockerfile from $WPCLI_SRC → $WPCLI_DST"
    fi
  fi

  COMPOSE_TPL="$APP_BASE/config/docker/compose.project.yml"
  COMPOSE_OUT="$PROJECT_BASE/docker/compose.project.yml"
  ensure_dir "$(dirname "$COMPOSE_OUT")"

  if $WHATIF; then
    whatif "Would copy $COMPOSE_TPL → $COMPOSE_OUT"
  else
    cp "$COMPOSE_TPL" "$COMPOSE_OUT"
    success "Copied $COMPOSE_TPL → $COMPOSE_OUT"
  fi
}

init_project() {
  # Proxy resources
  PROXY_SRC="$APP_BASE/config/proxy"
  PROXY_DST="$PROJECT_BASE/config/proxy"

  if [[ -d "$PROXY_SRC" ]]; then
    if [[ "$WHATIF" == true ]]; then
      whatif "Would copy proxy resources from $PROXY_SRC → $PROXY_DST"
    else
      mkdir -p "$PROXY_DST"
      cp -r "$PROXY_SRC"/* "$PROXY_DST"/
      info "Copied proxy resources from $PROXY_SRC → $PROXY_DST"
    fi
  else
    error "Proxy source directory not found: $PROXY_SRC"
  fi

  # WordPress resources ini
  WP_RESOURCES_SRC="$APP_BASE/config/wordpress/ptek-resources.ini"
  WP_RESOURCES_DST="$PROJECT_BASE/config/wordpress/ptek-resources.ini"

  if [[ -f "$WP_RESOURCES_SRC" ]]; then
    if [[ "$WHATIF" == true ]]; then
      whatif "Would copy WordPress resources ini from $WP_RESOURCES_SRC → $WP_RESOURCES_DST"
    else
      mkdir -p "$(dirname "$WP_RESOURCES_DST")"
      cp "$WP_RESOURCES_SRC" "$WP_RESOURCES_DST"
      info "Copied WordPress resources ini from $WP_RESOURCES_SRC → $WP_RESOURCES_DST"
    fi
  else
    error "WordPress resources ini not found: $WP_RESOURCES_SRC" 
  fi

  # Project control script
  PROJECT_SCRIPT_SRC="$APP_BASE/config/bsh/project.sh.tpl"
  PROJECT_SCRIPT_DST="$PROJECT_BASE/bin/project.sh"

  if [[ -f "$PROJECT_SCRIPT_SRC" ]]; then
    if [[ "$WHATIF" == true ]]; then
      whatif "Would install project control script from $PROJECT_SCRIPT_SRC → $PROJECT_SCRIPT_DST"
    else
      mkdir -p "$(dirname "$PROJECT_SCRIPT_DST")"
      cp "$PROJECT_SCRIPT_SRC" "$PROJECT_SCRIPT_DST"
      chmod +x "$PROJECT_SCRIPT_DST"
      info "Installed project control script at $PROJECT_SCRIPT_DST"
    fi
  fi
}

provision_project() {
  parse_options "$@"
  resolve_project
  docker_check

  case "$ACTION" in
    init)
      scaffold_directories
      init_project
      generate_env_file
      deploy_docker_assets
      ;;
    up)
      $WHATIF && whatif "docker compose up -d" || docker compose -f "$PROJECT_BASE/docker/compose.project.yml" up -d
      ;;
    down)
      $WHATIF && whatif "docker compose down" || docker compose -f "$PROJECT_BASE/docker/compose.project.yml" down
      ;;
    reset)
      if $WHATIF; then
        whatif "docker compose down && re-init"
      else
        docker compose -f "$PROJECT_BASE/docker/compose.project.yml" down
        scaffold_directories
        generate_env_file
        deploy_docker_assets
        docker compose -f "$PROJECT_BASE/docker/compose.project.yml" up -d
      fi
      ;;
    *)
      error "Unknown action: $ACTION"
      usage
      exit 1
      ;;
  esac

  success "Provision action '$ACTION' complete for $PROJECT ($HOST_DOMAIN)"
}

provision_project "$@"