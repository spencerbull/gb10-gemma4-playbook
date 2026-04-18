#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

load_env
require_target_transport_commands
show_target

log "Stopping the single-node vLLM container"
target_bash "cd '$TARGET_SPARK_DIR' && ./launch-cluster.sh --solo stop || true"
