#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

load_env
require_local_commands ssh
show_target

log "Stopping the single-node vLLM container"
remote_bash "cd '$REMOTE_REPO_DIR' && ./launch-cluster.sh --solo stop || true"
