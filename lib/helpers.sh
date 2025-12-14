#!/usr/bin/env bash
# Common helper functions for PtekWPDev

# Ensure a directory exists
ensure_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
  fi
}

# Copy a template file to a destination if it exists
copy_tpl() {
  local tpl="$1"
  local dest="$2"
  if [[ -f "$tpl" ]]; then
    cp "$tpl" "$dest"
    return 0
  else
    return 1
  fi
}

# Check if a required binary is available
check_binary() {
  local bin="$1"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "[ERR] Required binary '$bin' not found in PATH" >&2
    exit 1
  fi
}

# Expand environment variables in a file using envsubst
expand_env_file() {
  local src="$1"
  local dest="$2"
  if [[ -f "$src" ]]; then
    envsubst < "$src" > "$dest"
  else
    echo "[WARN] Template file $src not found" >&2
  fi
}

# === New: Backup utility for environments.json ===
backup_config() {
  local config_file="$1"
  local backup_dir
  backup_dir="$(dirname "$config_file")"
  local timestamp
  timestamp="$(date +%Y%m%d_%H%M%S)"
  local backup_file="${backup_dir}/$(basename "$config_file").bak_${timestamp}"

  if [[ -f "$config_file" ]]; then
    cp "$config_file" "$backup_file"
    echo "[INFO] Backup created: $backup_file"
  else
    echo "[WARN] Config file $config_file not found, skipping backup"
  fi
}

# Log a copy operation for auditability
log_copy() {
  local src="$1"
  local dest="$2"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"

  # Ensure audit log directory exists
  mkdir -p "${APP_BASE}/logs"

  echo "[$ts] COPY: $src → $dest" >> "${APP_BASE}/logs/assets.log"
}

# === New: WHAT-IF (dry run) support ===

# Global flag (default: false)
WHAT_IF=false

# Parse what-if option from args
# Usage: if parse_what_if "$1"; then shift; fi
parse_what_if() {
  case "$1" in
    -w|--what-if)
      WHAT_IF=true
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Run or preview an action
# Usage: run_or_preview "Description" command args...
run_or_preview() {
  local description="$1"
  shift
  if [[ "$WHAT_IF" == true ]]; then
    echo "[WHAT-IF] Would: $description"
  else
    "$@"
  fi
}

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
    echo "[INFO] Waiting for container '$container' to be up... (attempt $attempt/$retries)"
    sleep "$delay"
    (( attempt++ ))
  done

  echo "[ERR] Container '$container' is not running or reachable after $retries attempts."
  exit 1
}

# === Resolve container name for a service ===
resolve_container_name() {
  local compose_file="$1"
  local service="$2"

  local id
  id="$(docker compose -f "$compose_file" ps -q "$service" || true)"
  if [[ -z "$id" ]]; then
    echo ""
    return 1
  fi
  docker inspect --format '{{.Name}}' "$id" | sed 's/^\///'
}