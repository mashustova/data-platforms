#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
[[ -x "$HW5_DIR/.venv/bin/python" ]] || fail 'Run scripts/install_prefect.sh first'
export PREFECT_HOME="$HOME/.local/state/team17-hw5/prefect"
export PREFECT_API_URL=http://127.0.0.1:4200/api
export PREFECT_SERVER_ANALYTICS_ENABLED=false
export PREFECT_SERVER_EPHEMERAL_ENABLED=false
unset PREFECT_API_KEY
umask 077
mkdir -p "$PREFECT_HOME"
cd "$HW5_DIR"
exec .venv/bin/python flow.py "$@"
