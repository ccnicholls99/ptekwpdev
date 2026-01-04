#!/usr/bin/env bash

# Do not use...still experimental
echo "script_header_apply is non functional - do not use"
exit 0

set -Eeuo pipefail

# --- Error Handling ---------------------------------------------------------
COLOR_RED="\033[31m"
COLOR_RESET="\033[0m"
_ts() { date +"%Y-%m-%d %H:%M:%S"; }
err() { echo -e "${COLOR_RED}[$(_ts)] ERROR: $*${COLOR_RESET}" >&2; }

CALLER_PWD="$(pwd)"
trap 'err "Command failed (exit $?): $BASH_COMMAND"' ERR
trap 'cd "$CALLER_PWD" || true' EXIT
# ---------------------------------------------------------------------------

# Resolve APP_BASE from app/support/bin
APP_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SUPPORT_BASE="${APP_BASE}/app/support"
TEMPLATE_DIR="${SUPPORT_BASE}/templates"
HEADER_TEMPLATE="${TEMPLATE_DIR}/script_header.tpl"

usage() {
    cat <<EOF
Usage: script_header_apply.sh [options] <file1> [file2 ...]

Include mutation flags:
  -e+   Add    error.sh include
  -e-   Remove error.sh include
  -e?   Verify error.sh include

  -l+   Add    output.sh include (requires LOGFILE guard)
  -l-   Remove output.sh include
  -l?   Verify output.sh include

  -u+   Add    helpers.sh include
  -u-   Remove helpers.sh include
  -u?   Verify helpers.sh include

  -a+   Add    app_config.sh include
  -a-   Remove app_config.sh include
  -a?   Verify app_config.sh include

  -p+   Add    project_config.sh include (requires PROJECT_KEY guard)
  -p-   Remove project_config.sh include
  -p?   Verify project_config.sh include
EOF
    exit 1
}

# --- Parse include mutation flags ------------------------------------------
declare -A ACTIONS=()
declare -A INCLUDE_LINES=(
    [e]='source "${APP_BASE}/lib/error.sh"'
    [l]='source "${APP_BASE}/lib/output.sh"'
    [u]='source "${APP_BASE}/lib/helpers.sh"'
    [a]='source "${APP_BASE}/lib/app_config.sh"'
    [p]='source "${APP_BASE}/lib/project_config.sh"'
)
INCLUDE_ORDER=(e l u a p)

FILES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -[el uap][+\-\?])
            key="${1:1:1}"
            op="${1:2:1}"
            ACTIONS["$key"]="$op"
            ;;
        -*)
            err "Unknown option: $1"
            usage
            ;;
        *)
            FILES+=("$1")
            ;;
    esac
    shift
done

[[ ${#FILES[@]} -gt 0 ]] || usage

# --- Helper: mutate include block ------------------------------------------
mutate_includes() {
    local file="$1"
    local tmp="$(mktemp)"

    # Extract body after header (first 50 lines)
    local body="$(tail -n +51 "$file")"

    # Build new include block
    local new_block=()
    local verify_failed=0

    for key in "${INCLUDE_ORDER[@]}"; do
        local op="${ACTIONS[$key]:-}"
        local line="${INCLUDE_LINES[$key]}"

        case "$op" in
            +)  new_block+=("$line") ;;
            -)  ;;  # skip/remove
            \?) # verify
                if ! grep -Fq "$line" <<< "$body"; then
                    err "Verify failed: missing include '$line' in $file"
                    verify_failed=1
                fi
                ;;
        esac
    done

    [[ $verify_failed -eq 0 ]] || return 2

    # Write header
    cat "$HEADER_TEMPLATE" > "$tmp"

    # Write include block if non-empty
    if [[ ${#new_block[@]} -gt 0 ]]; then
        echo "" >> "$tmp"
        echo "# --- Generated Includes (managed by script_header_* tools) -------------------" >> "$tmp"
        echo "# NOTE:" >> "$tmp"
        echo "#   This block is automatically generated." >> "$tmp"
        echo "#   Do NOT edit these lines manually." >> "$tmp"
        echo "#   Use script_header_apply.sh, script_header_fix.sh, or script_header_check.sh" >> "$tmp"
        echo "#   to add, remove, or verify includes." >> "$tmp"
        echo "" >> "$tmp"

        for key in "${INCLUDE_ORDER[@]}"; do
            local line="${INCLUDE_LINES[$key]}"
            if printf '%s\n' "${new_block[@]}" | grep -Fq "$line"; then

                # Insert guards where required
                case "$key" in
                    l)
                        echo ': "${LOGFILE:?LOGFILE must be exported before sourcing output.sh}"' >> "$tmp"
                        ;;
                    p)
                        echo ': "${PROJECT_KEY:?PROJECT_KEY must be exported before sourcing project_config.sh}"' >> "$tmp"
                        ;;
                esac

                echo "$line" >> "$tmp"
                echo "" >> "$tmp"
            fi
        done

        echo "# ---------------------------------------------------------------------------" >> "$tmp"
        echo "" >> "$tmp"
    fi

    # Append body
    echo "$body" >> "$tmp"

    mv "$tmp" "$file"
}

# --- Apply header + include mutations --------------------------------------
for file in "${FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        err "Not a file: $file"
        continue
    fi

    perms="$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file")"

    # Always apply canonical header
    tmp="$(mktemp)"
    cat "$HEADER_TEMPLATE" > "$tmp"
    tail -n +51 "$file" >> "$tmp" || true
    mv "$tmp" "$file"

    # Mutate include block
    if ! mutate_includes "$file"; then
        err "Include verification failed for $file"
        continue
    fi

    chmod "$perms" "$file"
    echo "Applied header + includes: $file"
done