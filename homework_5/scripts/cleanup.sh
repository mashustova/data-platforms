#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
set_run "${1:?Usage: cleanup.sh RUN_ID}"
[[ -f "$EVIDENCE_DIR/submission.started" ]] || { printf 'No submission was started for %s\n' "$RUN_ID"; exit 0; }
collect_spark_report || true
app_id=$(python3 "$HW5_DIR/scripts/resolve_application_id.py" "$EVIDENCE_DIR/spark-report.json" "$EVIDENCE_DIR/spark-submit.log")
[[ -n "$app_id" ]] || fail 'No unambiguous own application ID. Inspect spark-submit.log and YARN; cleanup is unconfirmed'
nn_yarn application -status "$app_id" > "$EVIDENCE_DIR/yarn-cleanup-status.txt" 2>&1
state=$(python3 - "$EVIDENCE_DIR/yarn-cleanup-status.txt" "$app_id" "$RUN_ID" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
def field(name):
    match = re.search(r'^\s*' + re.escape(name) + r'\s*:\s*(.*?)\s*$', text, re.M)
    if not match:
        raise SystemExit('Cannot verify YARN application identity: missing ' + name)
    return match[1]
if (field('Application-Id') != sys.argv[2]
        or field('Application-Name') != 'team17-hw5-daily-sales-' + sys.argv[3]
        or field('User') != 'hadoop'):
    raise SystemExit('Refusing cleanup: YARN application identity differs from this HW5 run')
print(field('State'))
PY
)
case "$state" in
  FINISHED|FAILED|KILLED) ;;
  *)
    nn_yarn application -kill "$app_id" > "$EVIDENCE_DIR/yarn-cleanup-kill.txt" 2>&1
    deadline=$((SECONDS + 30))
    while :; do
      nn_yarn application -status "$app_id" > "$EVIDENCE_DIR/yarn-cleanup-status.txt" 2>&1
      if grep -Eq '^[[:space:]]*State[[:space:]]*:[[:space:]]*(FINISHED|FAILED|KILLED)[[:space:]]*$' "$EVIDENCE_DIR/yarn-cleanup-status.txt"; then
        break
      fi
      [[ $SECONDS -lt $deadline ]] || fail "Own application $app_id is still active; cleanup unconfirmed"
      sleep 2
    done
    ;;
esac
python3 - "$EVIDENCE_DIR/cleanup.json" "$app_id" <<'PY'
import json
from pathlib import Path
import sys
Path(sys.argv[1]).write_text(json.dumps({'application_id': sys.argv[2], 'status': 'terminal_state_confirmed'}, indent=2) + '\n')
PY
printf 'Own application is terminal: %s\n' "$app_id"
