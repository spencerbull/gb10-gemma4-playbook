#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

load_env
require_target_transport_commands
show_target

log "Container status"
target_bash "docker ps --format '{{.Names}} {{.Image}} {{.Status}}' | grep '^vllm_node ' || true"

log "GPU utilization"
target_bash "nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader"

log "API models"
target_bash "curl -sf http://127.0.0.1:$VLLM_PORT/v1/models"
