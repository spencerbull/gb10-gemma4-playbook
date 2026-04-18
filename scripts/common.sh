#!/usr/bin/env bash
set -euo pipefail

PLAYBOOK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$PLAYBOOK_ROOT/.env}"

DEFAULT_MODEL_ID="bg-digitalservices/Gemma-4-26B-A4B-it-NVFP4A16"
DEFAULT_RECIPE="gemma4-26b-a4b-nvfp4a16"

log() {
    printf '[%s] %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S UTC')" "$*"
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_local_commands() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "Missing required local command: $cmd"
    done
}

load_env() {
    [ -f "$ENV_FILE" ] || die "Missing $ENV_FILE. Copy .env.example to .env and update it first."
    # shellcheck disable=SC1090
    source "$ENV_FILE"

    : "${TARGET_HOST:?TARGET_HOST is required in .env}"

    TARGET_USER="${TARGET_USER:-dell}"
    TARGET_PORT="${TARGET_PORT:-22}"
    if [ -n "${TARGET_PLAYBOOK_DIR:-}" ]; then
        TARGET_PLAYBOOK_DIR="$TARGET_PLAYBOOK_DIR"
    elif [ -n "${REMOTE_PLAYBOOK_DIR:-}" ]; then
        TARGET_PLAYBOOK_DIR="$REMOTE_PLAYBOOK_DIR"
    elif [ -n "${REMOTE_REPO_DIR:-}" ]; then
        case "$REMOTE_REPO_DIR" in
            */spark-vllm-docker)
                TARGET_PLAYBOOK_DIR="${REMOTE_REPO_DIR%/spark-vllm-docker}/gb10-gemma4-playbook"
                ;;
            *)
                TARGET_PLAYBOOK_DIR="$REMOTE_REPO_DIR"
                ;;
        esac
    else
        TARGET_PLAYBOOK_DIR="/home/$TARGET_USER/src/github.com/spencerbull/gb10-gemma4-playbook"
    fi
    TARGET_SPARK_DIR="$TARGET_PLAYBOOK_DIR/spark-vllm-docker"
    MODEL_ID="${MODEL_ID:-$DEFAULT_MODEL_ID}"
    RECIPE="${RECIPE:-$DEFAULT_RECIPE}"
    VLLM_PORT="${VLLM_PORT:-8000}"
    GEMMA4_THINKING_DEFAULT="${GEMMA4_THINKING_DEFAULT:-auto}"
    BENCHMARK_RUNS="${BENCHMARK_RUNS:-2}"
    BENCHMARK_MAX_TOKENS="${BENCHMARK_MAX_TOKENS:-256}"
    BENCHMARK_LARGE_TARGET_TOKENS="${BENCHMARK_LARGE_TARGET_TOKENS:-240000}"

    TARGET_SSH="$TARGET_USER@$TARGET_HOST"
    REPORTS_DIR="$PLAYBOOK_ROOT/reports"
    mkdir -p "$REPORTS_DIR"

    TARGET_IS_LOCAL=0
    if [ "$PLAYBOOK_ROOT" = "$TARGET_PLAYBOOK_DIR" ]; then
        case "$TARGET_HOST" in
            127.0.0.1|localhost|$(hostname)|$(hostname -s)|$(hostname -f 2>/dev/null || hostname))
                TARGET_IS_LOCAL=1
                ;;
        esac
    fi
}

target_bash() {
    local cmd="$1"
    if [ "$TARGET_IS_LOCAL" = "1" ]; then
        bash -lc "$cmd"
        return 0
    fi

    local escaped
    printf -v escaped '%q' "$cmd"
    ssh -p "$TARGET_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$TARGET_SSH" "bash -lc $escaped"
}

copy_from_target() {
    local src="$1"
    local dst="$2"

    if [ "$TARGET_IS_LOCAL" = "1" ]; then
        cp "$src" "$dst"
        return 0
    fi

    rsync -az "$TARGET_SSH:$src" "$dst"
}

require_target_transport_commands() {
    if [ "$TARGET_IS_LOCAL" = "1" ]; then
        return 0
    fi

    require_local_commands ssh rsync
}

sync_playbook() {
    if [ "$TARGET_IS_LOCAL" = "1" ]; then
        log "Playbook is already running from the target checkout; skipping sync"
        return 0
    fi

    log "Syncing gb10-gemma4-playbook to $TARGET_SSH:$TARGET_PLAYBOOK_DIR"
    target_bash "mkdir -p '$TARGET_PLAYBOOK_DIR'"
    rsync -az --delete \
        --filter='P .git' \
        --exclude '.git' \
        --exclude '.pytest_cache' \
        --exclude '__pycache__' \
        --exclude '.venv' \
        --exclude '.env' \
        --exclude 'reports/*.md' \
        --exclude 'benchmarks/*.md' \
        "$PLAYBOOK_ROOT/" "$TARGET_SSH:$TARGET_PLAYBOOK_DIR/"
}

wait_for_api() {
    local attempts="${1:-60}"
    local sleep_seconds="${2:-10}"
    local i
    for i in $(seq 1 "$attempts"); do
        if target_bash "docker logs vllm_node 2>&1 | grep -q 'Uvicorn running on'"; then
            if target_bash "curl -sf http://127.0.0.1:$VLLM_PORT/v1/models >/dev/null"; then
                return 0
            fi
        fi
        sleep "$sleep_seconds"
    done
    return 1
}

show_target() {
    log "Target host: $TARGET_SSH"
    log "Target playbook: $TARGET_PLAYBOOK_DIR"
    log "Target spark repo: $TARGET_SPARK_DIR"
    if [ "$TARGET_IS_LOCAL" = "1" ]; then
        log "Execution mode: local"
    else
        log "Execution mode: ssh"
    fi
    log "Model: $MODEL_ID"
    log "Recipe: $RECIPE"
}

recipe_extra_args() {
    case "$GEMMA4_THINKING_DEFAULT" in
        auto)
            ;;
        on)
            printf -- " -- --default-chat-template-kwargs '{\"enable_thinking\": true}'"
            ;;
        off)
            printf -- " -- --default-chat-template-kwargs '{\"enable_thinking\": false}'"
            ;;
        *)
            die "GEMMA4_THINKING_DEFAULT must be one of: auto, on, off"
            ;;
    esac
}
