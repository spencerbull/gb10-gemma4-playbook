#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SKIP_BUILD=0
SKIP_DOWNLOAD=0
SKIP_START=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --skip-build)
            SKIP_BUILD=1
            ;;
        --skip-download)
            SKIP_DOWNLOAD=1
            ;;
        --skip-start)
            SKIP_START=1
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
    shift
done

load_env
require_local_commands ssh rsync curl git python3
show_target
sync_playbook

log "Checking target Docker and GPU visibility"
remote_bash "docker --version >/dev/null && nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader"

log "Ensuring uv is installed on the target"
remote_bash "command -v uvx >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh"

if [ "$SKIP_BUILD" -eq 0 ]; then
    log "Building the TF5 vLLM image on the target"
    remote_bash "cd '$REMOTE_SPARK_DIR' && ./build-and-copy.sh --tf5"
fi

if [ "$SKIP_DOWNLOAD" -eq 0 ]; then
    log "Downloading the model on the target"
    remote_bash "cd '$REMOTE_SPARK_DIR' && ./hf-download.sh '$MODEL_ID'"
fi

if [ "$SKIP_START" -eq 0 ]; then
    log "Launching the single-node Gemma4 recipe"
    remote_bash "cd '$REMOTE_SPARK_DIR' && ./launch-cluster.sh --solo stop || true"
    EXTRA_ARGS="$(recipe_extra_args)"
    remote_bash "cd '$REMOTE_SPARK_DIR' && ./run-recipe.sh '$RECIPE' --solo -d$EXTRA_ARGS"

    log "Waiting for the API to become healthy"
    wait_for_api 60 10 || die "The vLLM API did not become healthy in time"
fi

log "Bootstrap complete"
remote_bash "curl -sf http://127.0.0.1:$VLLM_PORT/v1/models"
