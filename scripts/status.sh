#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

load_env
require_local_commands ssh
show_target

log "Container status"
remote_bash "docker ps --format '{{.Names}} {{.Image}} {{.Status}}' | grep '^vllm_node ' || true"

log "GPU utilization"
remote_bash "nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader"

log "API models"
remote_bash "curl -sf http://127.0.0.1:$VLLM_PORT/v1/models"
