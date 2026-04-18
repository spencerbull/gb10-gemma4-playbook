#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

RUNS_OVERRIDE=""
MAX_TOKENS_OVERRIDE=""
LARGE_TARGET_OVERRIDE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --runs)
            RUNS_OVERRIDE="$2"
            shift
            ;;
        --max-tokens)
            MAX_TOKENS_OVERRIDE="$2"
            shift
            ;;
        --large-target-tokens)
            LARGE_TARGET_OVERRIDE="$2"
            shift
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
    shift
done

load_env
require_local_commands ssh rsync

RUNS="${RUNS_OVERRIDE:-$BENCHMARK_RUNS}"
MAX_TOKENS="${MAX_TOKENS_OVERRIDE:-$BENCHMARK_MAX_TOKENS}"
LARGE_TARGET_TOKENS="${LARGE_TARGET_OVERRIDE:-$BENCHMARK_LARGE_TARGET_TOKENS}"

show_target
sync_playbook

log "Running the benchmark on the target"
remote_bash "cd '$REMOTE_SPARK_DIR' && python3 benchmarks/chat_completion_benchmark.py --api-base http://127.0.0.1:$VLLM_PORT --runs '$RUNS' --max-tokens '$MAX_TOKENS' --large-target-tokens '$LARGE_TARGET_TOKENS' --output benchmarks/gemma4-26b-a4b-it-nvfp4a16-metrics.md"

SAFE_HOST="${TARGET_HOST//[^A-Za-z0-9._-]/-}"
STAMP="$(date -u +'%Y%m%d-%H%M%S')"
LOCAL_REPORT="$REPORTS_DIR/${STAMP}-${SAFE_HOST}-gemma4-26b-a4b-it-nvfp4a16-metrics.md"

rsync -az "$SSH_TARGET:$REMOTE_SPARK_DIR/benchmarks/gemma4-26b-a4b-it-nvfp4a16-metrics.md" "$LOCAL_REPORT"
cp "$LOCAL_REPORT" "$REPORTS_DIR/latest.md"

log "Benchmark report saved to $LOCAL_REPORT"
log "Benchmark report copied to $REPORTS_DIR/latest.md"
