#!/usr/bin/env bash
# Common helper functions for PtekWPDev

# Prevent double-sourcing
[[ -n "${PTEK_LIB_HELPERS_LOADED:-}" ]] && return
PTEK_LIB_HELPERS_LOADED=1

# ------------------------------------------------------------------------------
# Optional Dependencies
# ------------------------------------------------------------------------------
# Only load logging if helper functions require it
if [[ -z "${PTEK_LIB_OUTPUT_LOADED:-}" ]]; then
    # shellcheck source=/dev/null
    source "${PTEK_APP_BASE}/lib/output.sh"
fi

# === Usage documentation ===
helpers_usage() {
  cat <<'EOF'
PtekWPDev Helpers - Available Functions
---------------------------------------

Directory utilities:
  ensure_dir <dir>
    Ensure a directory exists (mkdir -p if missing).

Copy utilities:
  copy_tpl <tpl> <dest>
    Copy a template file to destination if it exists.
  copy_if_newer <src> <dst> <description> [patch_cmd]
    Copy a file only if source is newer than target.
    Optionally apply a patch command (like sed) before writing.

Binary checks:
  check_binary <bin>
    Verify that a required binary is available in PATH.

Env expansion:
  expand_env_file <src> <dest>
    Expand environment variables in a template file using envsubst.
  log_env_expansion <project_json> <env_file>
    Sanity check that placeholders in env_file were expanded.

Backup utility:
  backup_config <config_file>
    Create a timestamped backup of environments.json or other config.

Audit logging:
  log_copy <src> <dest>
    Log a copy operation to LOGFILE for auditability.

WHAT-IF support:
  parse_what_if <arg>
    Parse -w/--what-if flag to enable dry-run mode.
  run_or_preview <description> <command> [args...]
    Run or preview an action depending on WHAT_IF flag.

Docker helpers:
  require_container_up <container> [retries] [delay]
    Wait until a container is running and reachable.
  resolve_container_name <compose_file> <service>
    Resolve container name for a given service in a compose file.
  docker_check
    Verify Docker and Docker Compose availability.

EOF
}

confirm() {
  local prompt="$1"
  read -r -p "$prompt (y/N): " reply
  case "$reply" in
    [yY][eE][sS]|[yY]) return 0 ;;
    *) return 1 ;;
  esac
}

# === Directory utilities ===
ensure_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || mkdir -p "$dir"
}

# === Copy utilities ===

# Copy a template file to a destination if it exists
copy_tpl() {
  local tpl="$1"
  local dest="$2"
  if [[ -f "$tpl" ]]; then
    cp "$tpl" "$dest"
    log_copy "$tpl" "$dest"
    return 0
  else
    return 1
  fi
}

# Copy a file only if the source is newer than the target.
# Optionally apply a patch command (like sed) before writing.
# Usage: copy_if_newer <src> <dst> <description> [patch_cmd]
copy_if_newer() {
  local src="$1" dst="$2" desc="$3" patch_cmd="${4:-}"

  if [[ ! -f "$src" ]]; then
    error "Source file not found: $src"
    return 1
  fi

  if [[ ! -f "$dst" || "$src" -nt "$dst" ]]; then
    if [[ "$WHAT_IF" == true ]]; then
      whatif "Would copy $desc from $src → $dst"
    else
      ensure_dir "$(dirname "$dst")"
      if [[ -n "$patch_cmd" ]]; then
        $patch_cmd "$src" > "$dst"
        info "Patched and copied $desc from $src → $dst"
      else
        cp "$src" "$dst"
        info "Copied $desc from $src → $dst"
      fi
      log_copy "$src" "$dst"
    fi
  else
    info "Skipped $desc (target newer than source: $dst)"
  fi
}

# === Binary checks ===
# Usage: check_binary docker git jq
check_binary() {
  local missing=()
  for bin in "$@"; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      missing+=("$bin")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    error "Required binaries not found: ${missing[*]}"
    exit 1
  fi

  for bin in "$@"; do
    local version
    version="$($bin --version 2>/dev/null || echo "available")"
    info "$bin available: $version"
  done
}

# === Env expansion ===
expand_env_file() {
  local src="$1" dest="$2"
  if [[ -f "$src" ]]; then
    envsubst < "$src" > "$dest"
    log_copy "$src" "$dest"
  else
    warn "Template file $src not found"
  fi
}

# === Backup utility ===
backup_config() {
  local config_file="$1"
  local backup_dir="$(dirname "$config_file")"
  local timestamp="$(date +%Y%m%d_%H%M%S)"
  local backup_file="${backup_dir}/$(basename "$config_file").${timestamp}.bak"

  if [[ -f "$config_file" ]]; then
    cp "$config_file" "$backup_file"
    info "Backup created: $backup_file"
  else
    warn "Config file $config_file not found, skipping backup"
  fi
}

# === Audit logging ===
log_copy() {
  local src="$1" dest="$2"
  local ts="$(date '+%Y-%m-%d %H:%M:%S')"

  if [[ -z "${LOGFILE:-}" ]]; then
    echo "[WARN] LOGFILE not set, cannot log copy operation" >&2
    return 1
  fi

  echo "[$ts] COPY: $src → $dest" >> "$LOGFILE"
}

# === WHAT-IF support ===
WHAT_IF=false
parse_what_if() {
  case "$1" in
    -w|--what-if) WHAT_IF=true; return 0 ;;
    *) return 1 ;;
  esac
}

run_or_preview() {
  local description="$1"; shift
  if [[ "$WHAT_IF" == true ]]; then
    echo "[WHAT-IF] Would: $description"
  else
    "$@"
  fi
}

# === Docker helpers ===
require_container_up() {
  local container="$1"
  local retries="${2:-10}"
  local delay="${3:-1}"

  local attempt=1
  while (( attempt <= retries )); do
    if docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null | grep -q true; then
      if docker exec "$container" true >/dev/null 2>&1; then
        return 0
      fi
    fi
    info "Waiting for container '$container' to be up... (attempt $attempt/$retries)"
    sleep "$delay"
    (( attempt++ ))
  done

  error "Container '$container' is not running or reachable after $retries attempts."
  exit 1
}

resolve_container_name() {
  local compose_file="$1" service="$2"
  local id
  id="$(docker compose -f "$compose_file" ps -q "$service" || true)"
  if [[ -z "$id" ]]; then
    echo ""
    return 1
  fi
  docker inspect --format '{{.Name}}' "$id" | sed 's/^\///'
}

docker_check() {
  if ! command -v docker >/dev/null 2>&1; then
    error "Docker is not installed or not in PATH. Please install Docker before running this script."
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    error "Docker daemon is not running or not accessible. Please start Docker before running this script."
    exit 1
  fi

  if ! docker compose version >/dev/null 2>&1; then
    error "Docker Compose v2 is not available. Please install or upgrade Docker Compose."
    exit 1
  fi

  info "Docker and Docker Compose are available and running."
}

# === Env expansion sanity check ===
log_env_expansion() {
  local project_json="$1" env_file="$2"

  info "Sanity check: keys expanded into $env_file"

  for key in $(echo "$project_json" | jq -r 'keys[]'); do
    [[ "$key" == "secrets" ]] && continue
    val=$(echo "$project_json" | jq -r ".${key}")
    if grep -q "{{${key}}}" "$env_file"; then
      warn "⚠️ Placeholder {{${key}}} still present in $env_file"
    else
      info "✔ Expanded ${key} → ${val}"
    fi
  done

  secrets_json=$(echo "$project_json" | jq -r '.secrets // empty')
  if [[ -n "$secrets_json" && "$secrets_json" != "null" ]]; then
    for key in $(echo "$secrets_json" | jq -r 'keys[]'); do
      if grep -q "{{${key}}}" "$env_file"; then
        warn "⚠️ Secret placeholder {{${key}}} still present in $env_file"
      else
        info "✔ Expanded secret ${key} → [*****]"
      fi
    done
  fi
}

# === Git availability check ===
git_check() {
  if ! command -v git >/dev/null 2>&1; then
    error "Git is not installed or not in PATH. Please install Git before running this script."
    exit 1
  fi

  # Optional: sanity check version
  local version
  version="$(git --version 2>/dev/null)"
  info "Git available: $version"
}

ptek_generate_secret() {
  head -c 32 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 16
}

# === Dev code deployment ===
deploy_dev_code() {
  local source="$1"
  local target_subdir="$2"   # "themes" or "plugins"

  if [[ -z "$source" ]]; then
    warn "No dev source specified, skipping deployment"
    return 0
  fi

  # Ensure container is up
  require_container_up "$WP_CONTAINER"

  if [[ "$WHAT_IF" == true ]]; then
    whatif "Deploy $source → $WP_CONTAINER:$WP_VOLUME_PATH/$target_subdir"
    return 0
  fi

  if [[ -d "$source" ]]; then
    info "Deploying local dev source $source → $WP_CONTAINER:$WP_VOLUME_PATH/$target_subdir"
    docker cp "$source" "$WP_CONTAINER:$WP_VOLUME_PATH/$target_subdir"
  elif [[ "$source" =~ ^git@|^https:// ]]; then
    tmpdir="$(mktemp -d)"
    info "Cloning git repo $source into $tmpdir"
    git clone "$source" "$tmpdir"
    info "Deploying cloned repo → $WP_CONTAINER:$WP_VOLUME_PATH/$target_subdir"
    docker cp "$tmpdir" "$WP_CONTAINER:$WP_VOLUME_PATH/$target_subdir"
    rm -rf "$tmpdir"
  else
    error "Unsupported dev source: $source"
    return 1
  fi

  info "Deployment complete: $target_subdir"
}