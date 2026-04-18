#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

load_env
require_local_commands ssh rsync
show_target
sync_playbook

log "Restarting the single-node Gemma4 recipe"
remote_bash "cd '$REMOTE_SPARK_DIR' && ./launch-cluster.sh --solo stop || true"
EXTRA_ARGS="$(recipe_extra_args)"
remote_bash "cd '$REMOTE_SPARK_DIR' && ./run-recipe.sh '$RECIPE' --solo -d$EXTRA_ARGS"

log "Waiting for the API to become healthy"
wait_for_api 60 10 || die "The vLLM API did not become healthy in time"

remote_bash "curl -sf http://127.0.0.1:$VLLM_PORT/v1/models"
