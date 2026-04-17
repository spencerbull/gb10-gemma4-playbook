#!/usr/bin/env bash
set -euo pipefail

PLAYBOOK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMODULE_DIR="$PLAYBOOK_ROOT/spark-vllm-docker"
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
    REMOTE_REPO_DIR="${REMOTE_REPO_DIR:-/home/$TARGET_USER/src/github.com/spencerbull/spark-vllm-docker}"
    MODEL_ID="${MODEL_ID:-$DEFAULT_MODEL_ID}"
    RECIPE="${RECIPE:-$DEFAULT_RECIPE}"
    VLLM_PORT="${VLLM_PORT:-8000}"
    GEMMA4_REASONING_MODE="${GEMMA4_REASONING_MODE:-auto}"
    BENCHMARK_RUNS="${BENCHMARK_RUNS:-2}"
    BENCHMARK_MAX_TOKENS="${BENCHMARK_MAX_TOKENS:-256}"
    BENCHMARK_LARGE_TARGET_TOKENS="${BENCHMARK_LARGE_TARGET_TOKENS:-240000}"

    SSH_TARGET="$TARGET_USER@$TARGET_HOST"
    REPORTS_DIR="$PLAYBOOK_ROOT/reports"
    mkdir -p "$REPORTS_DIR"
}

remote_bash() {
    local cmd="$1"
    local escaped
    printf -v escaped '%q' "$cmd"
    ssh -p "$TARGET_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$SSH_TARGET" "bash -lc $escaped"
}

sync_submodule() {
    log "Syncing spark-vllm-docker to $SSH_TARGET:$REMOTE_REPO_DIR"
    remote_bash "mkdir -p '$REMOTE_REPO_DIR'"
    rsync -az --delete \
        --exclude '.git' \
        --exclude '.pytest_cache' \
        --exclude '__pycache__' \
        --exclude '.venv' \
        --exclude 'benchmarks/*.md' \
        "$SUBMODULE_DIR/" "$SSH_TARGET:$REMOTE_REPO_DIR/"
}

wait_for_api() {
    local attempts="${1:-60}"
    local sleep_seconds="${2:-10}"
    local i
    for i in $(seq 1 "$attempts"); do
        if remote_bash "curl -sf http://127.0.0.1:$VLLM_PORT/v1/models >/dev/null"; then
            return 0
        fi
        sleep "$sleep_seconds"
    done
    return 1
}

show_target() {
    log "Target host: $SSH_TARGET"
    log "Remote repo: $REMOTE_REPO_DIR"
    log "Model: $MODEL_ID"
    log "Recipe: $RECIPE"
}

recipe_extra_args() {
    case "$GEMMA4_REASONING_MODE" in
        auto)
            ;;
        on)
            printf -- " -- --default-chat-template-kwargs '{\"enable_thinking\": true}'"
            ;;
        off)
            printf -- " -- --default-chat-template-kwargs '{\"enable_thinking\": false}'"
            ;;
        *)
            die "GEMMA4_REASONING_MODE must be one of: auto, on, off"
            ;;
    esac
}
