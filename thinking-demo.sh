#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PYTHON="$ROOT/.venv/bin/python"

[ -x "$PYTHON" ] || {
    echo "Error: missing $PYTHON. Run ./setup-python.sh first." >&2
    exit 1
}

exec "$PYTHON" "$ROOT/examples/thinking_demo.py" "$@"
