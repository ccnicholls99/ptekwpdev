#!/usr/bin/env bash
#
# Provision script for WordPress dev environments (ptekwpdev)
#

set -euo pipefail

APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT=""
CONFIG_BASE="$HOME/.ptekwpdev"
CONFIG_FILE="$CONFIG_BASE/environments.json"
WHAT_IF=false
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
        WHAT_IF=true
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

  WORDPRESS_IMAGE=$(echo "$PROJECT_CONFIG" | jq -r '.wordpress_image // empty')
  WORDPRESS_SSL_PORT=$(echo "$PROJECT_CONFIG" | jq -r '.wordpress_ssl_port // empty')

  LOG_DIR="$PROJECT_BASE/app/logs"
  ensure_dir "$LOG_DIR"
  LOGFILE="$LOG_DIR/provision.log"
  export LOGFILE
  log_header "Provision: $PROJECT"
  #exec > >(tee -a "$LOGFILE") 2>&1

  info "Resolved project: $PROJECT_BASE (domain=$HOST_DOMAIN)"
}

scaffold_directories() {
  if $WHAT_IF; then
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

  if $WHAT_IF; then
    whatif "Would generate .env from $TPL_ENV → $ENV_FILE"
    return
  fi

  # Copy template into place
  cp "$TPL_ENV" "$ENV_FILE"

  # Load project-specific values from environments.json
  project_json=$(jq -r --arg pr "$PROJECT" '.environments[$pr]' "$CONFIG_FILE")

  # --------------------------------------------------------------------
  # Build derived values that are NOT stored in environments.json
  # --------------------------------------------------------------------
  derived_json=$(jq -n \
    --arg project_name "$PROJECT" \
    --arg project_domain "$HOST_DOMAIN" \
    --arg app_base "$APP_BASE" \
    --arg build_home "$APP_BASE" \
    --arg project_base "$PROJECT_BASE" \
    --arg wordpress_image "$WORDPRESS_IMAGE" \
    --arg wordpress_ssl_port "$WORDPRESS_SSL_PORT" \
    '{
      project_name: $project_name,
      project_domain: $project_domain,
      app_base: $app_base,
      build_home: $build_home,
      project_base: $project_base,
      wordpress_image: $wordpress_image,
      wordpress_ssl_port: $wordpress_ssl_port
    }'
  )

  # --------------------------------------------------------------------
  # Merge project_json + derived_json
  # --------------------------------------------------------------------
  merged_json=$(jq -s '.[0] * .[1]' \
    <(echo "$project_json") \
    <(echo "$derived_json")
  )

  # --------------------------------------------------------------------
  # Replace all {{placeholders}} using merged_json
  # --------------------------------------------------------------------
  for key in $(echo "$merged_json" | jq -r 'keys[]'); do
    [[ "$key" == "secrets" ]] && continue
    val=$(echo "$merged_json" | jq -r ".${key}")
    safe_val=$(printf '%s\n' "$val" | sed 's/[&/\]/\\&/g')
    sed -i "s|{{${key}}}|${safe_val}|g" "$ENV_FILE"
  done

  # --------------------------------------------------------------------
  # Replace secrets (masked in logs)
  # --------------------------------------------------------------------
  secrets_json=$(echo "$project_json" | jq -r '.secrets // empty')
  if [[ -n "$secrets_json" && "$secrets_json" != "null" ]]; then
    for key in $(echo "$secrets_json" | jq -r 'keys[]'); do
      val=$(echo "$secrets_json" | jq -r ".${key}")
      safe_val=$(printf '%s\n' "$val" | sed 's/[&/\]/\\&/g')
      info "Replacing {{${key}}} with [*****]"
      sed -i "s|{{${key}}}|${safe_val}|g" "$ENV_FILE"
    done
  fi

  # --------------------------------------------------------------------
  # Log final expansion
  # --------------------------------------------------------------------
  log_env_expansion "$merged_json" "$ENV_FILE"
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
    if [[ "$WHAT_IF" == true ]]; then
      whatif "Would copy project Docker ignore file from $DOCKERIGNORE_SRC → $DOCKERIGNORE_DST"
    else
      cp "$DOCKERIGNORE_SRC" "$DOCKERIGNORE_DST"
      info "Copied project Docker ignore file from $DOCKERIGNORE_SRC → $DOCKERIGNORE_DST"
    fi
  fi

  # WordPress Dockerfile, replace image and version, then deploy to project
  # WordPress Dockerfile (patched with correct image version)
  # DOCKER_SRC="$APP_BASE/config/docker/Dockerfile.wordpress"
  # DOCKER_DST="$PROJECT_BASE/docker/Dockerfile.wordpress"
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
    if [[ "$WHAT_IF" == true ]]; then
      whatif "Would copy WP-CLI Dockerfile from $WPCLI_SRC → $WPCLI_DST"
    else
      copy_if_newer "$APP_BASE/config/docker/Dockerfile.wpcli" \
                  "$PROJECT_BASE/docker/Dockerfile.wpcli" \
                  "Dockerfile.wpcli" 
      info "Copied WP-CLI Dockerfile from $WPCLI_SRC → $WPCLI_DST"
    fi
  fi

  COMPOSE_TPL="$APP_BASE/config/docker/compose.project.yml"
  COMPOSE_OUT="$PROJECT_BASE/docker/compose.project.yml"
  ensure_dir "$(dirname "$COMPOSE_OUT")"

  if $WHAT_IF; then
    whatif "Would copy $COMPOSE_TPL → $COMPOSE_OUT"
  else
    cp "$COMPOSE_TPL" "$COMPOSE_OUT"
    success "Copied $COMPOSE_TPL → $COMPOSE_OUT"
  fi
}

deploy_project_config() {
  # Proxy resources
  PROXY_SRC="$APP_BASE/config/proxy"
  PROXY_DST="$PROJECT_BASE/config/proxy"

  if [[ -d "$PROXY_SRC" ]]; then
    if [[ "$WHAT_IF" == true ]]; then
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
    if [[ "$WHAT_IF" == true ]]; then
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
    if [[ "$WHAT_IF" == true ]]; then
      whatif "Would install project control script from $PROJECT_SCRIPT_SRC → $PROJECT_SCRIPT_DST"
    else
      mkdir -p "$(dirname "$PROJECT_SCRIPT_DST")"
      cp "$PROJECT_SCRIPT_SRC" "$PROJECT_SCRIPT_DST"
      chmod +x "$PROJECT_SCRIPT_DST"
      info "Installed project control script at $PROJECT_SCRIPT_DST"
    fi
  fi
}

sync_docs() {
  local source="$APP_BASE/config/doc"
  local target="$PROJECT_BASE/doc"

  mkdir -p "$target"

  for file in "$source"/*; do
    local filename
    filename=$(basename "$file")
    copy_if_newer "$file" "$target/$filename" "documentation file $filename"
  done
}

# === Deploy dev sources (themes/plugins) for the current project ===
# === Deploy dev sources (themes/plugins) for the current project ===
deploy_project_dev_sources() {
  local project_key="$PROJECT"

  if [[ -z "$PROJECT_CONFIG" ]]; then
    error "PROJECT_CONFIG is not defined. Did you run resolve_project()?"
    return 1
  fi

  info "Provisioning dev sources for project: $project_key"

  # Deploy themes
  for row in $(echo "$PROJECT_CONFIG" | jq -c ".projects[\"$project_key\"].dev_sources.themes[]?"); do
    local name source type
    name=$(echo "$row" | jq -r '.name')
    source=$(echo "$row" | jq -r '.source')
    type=$(echo "$row" | jq -r '.type')

    info "Provisioning theme: $name ($type)"
    deploy_dev_code "$source" "themes/$name"
  done

  # Deploy plugins
  for row in $(echo "$PROJECT_CONFIG" | jq -c ".projects[\"$project_key\"].dev_sources.plugins[]?"); do
    local name source type
    name=$(echo "$row" | jq -r '.name')
    source=$(echo "$row" | jq -r '.source')
    type=$(echo "$row" | jq -r '.type')

    info "Provisioning plugin: $name ($type)"
    deploy_dev_code "$source" "plugins/$name"
  done
}

init_project() {
 
      scaffold_directories
      deploy_project_config
      generate_env_file
      deploy_docker_assets
      # Ensure required binaries are available
      check_binary docker git jq

      # Sync documentation files
      sync_docs

      # Deploy theme code
      deploy_project_dev_sources
}

# Exxplicit UP action
do_up() {
  if [[ "$WHAT_IF" == true ]]; then
    whatif "docker compose up -d"
  else
    docker compose \
      --project-directory "$PROJECT_BASE/docker" \
      -f "$PROJECT_BASE/docker/compose.project.yml" \
      up -d
  fi
}

# Explicit DOWN action
do_down() {
  if [[ "$WHAT_IF" == true ]]; then
    whatif "docker compose down"
  else
    docker compose \
      --project-directory "$PROJECT_BASE/docker" \
      -f "$PROJECT_BASE/docker/compose.project.yml" \
      down
  fi
}

# Explicit RESET action
do_reset() {
  if [[ "$WHAT_IF" == true ]]; then
    whatif "docker compose down && re-init"
  else
    docker compose \
      --project-directory "$PROJECT_BASE/docker" \
      -f "$PROJECT_BASE/docker/compose.project.yml" \
      down

    scaffold_directories
    generate_env_file
    deploy_docker_assets

    docker compose \
      --project-directory "$PROJECT_BASE/docker" \
      -f "$PROJECT_BASE/docker/compose.project.yml" \
      up -d
  fi
}

provision_project() {
  parse_options "$@"
  resolve_project
  docker_check

  case "$ACTION" in
    init)
      if init_project; then
        if [[ "$WHAT_IF" == true ]]; then
          whatif "Init successful — would automatically perform UP action"
        else
          info "Init successful — automatically performing UP action"
          do_up
        fi
      else
        error "Init failed — not performing UP"
        return 1
      fi
      ;;

    up)
      do_up
      ;;

    down)
      do_down
      ;;

    reset)
      do_reset
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