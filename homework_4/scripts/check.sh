#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
set_run "${1:?Usage: check.sh RUN_ID}"
[[ -d "$EVIDENCE_DIR" ]] || fail 'No evidence directory for this run'
python3 - "$EVIDENCE_DIR/spark-report.json" <<'PY'
import json
from pathlib import Path
import sys

report = json.loads(Path(sys.argv[1]).read_text())
if report['status'] != 'verified_hive_table_and_parquet' or report['master'] != 'yarn' or not report.get('spark_stopped'):
    raise SystemExit('Spark report does not confirm YARN and Parquet validation')
PY
app_id=$(python3 - "$EVIDENCE_DIR/spark-report.json" <<'PY'
import json
from pathlib import Path
import re
import sys

app_id = json.loads(Path(sys.argv[1]).read_text())['application_id']
if not re.fullmatch(r'application_[0-9]+_[0-9]+', app_id):
    raise SystemExit('Invalid YARN application ID')
print(app_id)
PY
)
for attempt in {1..15}; do
  nn_yarn application -status "$app_id" > "$EVIDENCE_DIR/yarn-status.txt" 2>&1
  if grep -Eq 'Final-State[[:space:]]*:[[:space:]]*SUCCEEDED' "$EVIDENCE_DIR/yarn-status.txt"; then
    break
  fi
  if grep -Eq 'Final-State[[:space:]]*:[[:space:]]*(FAILED|KILLED)' "$EVIDENCE_DIR/yarn-status.txt"; then
    fail 'YARN reports a failed/killed application; inspect yarn-status.txt'
  fi
  sleep 2
done
python3 - "$EVIDENCE_DIR/yarn-status.txt" <<'PY'
from pathlib import Path
import re
import sys

status = Path(sys.argv[1]).read_text()
if not re.search(r'Final-State\s*:\s*SUCCEEDED\b', status):
    raise SystemExit('YARN does not report SUCCEEDED; see yarn-status.txt')
PY
nn_hdfs dfs -ls -R "$RUN_HDFS/daily_sales" > "$EVIDENCE_DIR/hdfs-output.txt"
nn_beeline -e "SET hive.fetch.task.conversion=more; SELECT dt,city,order_count,total_quantity,revenue FROM $HW4_DATABASE.$TABLE_NAME;" \
  > "$EVIDENCE_DIR/hive-rows.tsv" 2> "$EVIDENCE_DIR/hive-query.log"
nn_beeline -e "SHOW PARTITIONS $HW4_DATABASE.$TABLE_NAME;" \
  > "$EVIDENCE_DIR/hive-partitions.tsv" 2> "$EVIDENCE_DIR/hive-partitions.log"
python3 "$HW4_DIR/scripts/validate_fixture.py" \
  --hive-rows "$EVIDENCE_DIR/hive-rows.tsv" \
  --hive-partitions "$EVIDENCE_DIR/hive-partitions.tsv" \
  | tee "$EVIDENCE_DIR/verification.txt"
printf 'Verified YARN + Parquet + Hive: %s.%s (%s)\n' "$HW4_DATABASE" "$TABLE_NAME" "$app_id"
