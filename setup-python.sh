#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$ROOT/.venv"

command -v uv >/dev/null 2>&1 || {
    echo "Error: uv is required. Install uv first." >&2
    exit 1
}

cd "$ROOT"
uv venv "$VENV_DIR"
uv pip install --python "$VENV_DIR/bin/python" -r "$ROOT/examples/requirements.txt"

echo "Python environment ready at $VENV_DIR"
echo "Use ./thinking-demo.sh or ./tool-call-demo.sh"
