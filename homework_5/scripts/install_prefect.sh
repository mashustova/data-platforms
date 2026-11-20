#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
cd "$HW5_DIR"
python3 -c 'import sys; assert sys.version_info[:2] == (3, 12), "Use Python 3.12 for the pinned environment"'
if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi
.venv/bin/python -c 'import sys; assert sys.version_info[:2] == (3, 12), "Existing .venv must use Python 3.12"'
.venv/bin/python -m pip install --require-hashes -r requirements.txt
.venv/bin/python -m pip check
.venv/bin/python -c 'import prefect; assert prefect.__version__ == "3.4.10"; print("Prefect", prefect.__version__)'
