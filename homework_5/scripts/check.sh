#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
set_run "${1:?Usage: check.sh RUN_ID}"
require_marker spark
rm -f "$EVIDENCE_DIR/verified.ok" "$EVIDENCE_DIR/verification.json"
app_id=$(python3 - "$EVIDENCE_DIR/spark-report.json" "$RUN_ID" <<'PY'
import json
from pathlib import Path
import re
import sys

report = json.loads(Path(sys.argv[1]).read_text())
run_id = sys.argv[2]
base = 'hdfs://team-17-nn:9000/user/hadoop/mashustova/hw5/runs/' + run_id
if (report['status'] != 'verified_hive_table_and_parquet' or report['master'] != 'yarn'
        or not report.get('spark_stopped') or report['table'] != 'dp_mashustova_hw5.daily_sales_' + run_id
        or report['input'] != base + '/input/orders.csv' or report['output'] != base + '/daily_sales'
        or report['table_location'] != base + '/daily_sales'):
    raise SystemExit('Spark report does not confirm this HW5 run, YARN and table/Parquet validation')
app_id = report['application_id']
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
python3 - "$EVIDENCE_DIR/yarn-status.txt" "$app_id" "$RUN_ID" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
for label, expected in [('Application-Id', sys.argv[2]), ('Application-Name', 'team17-hw5-daily-sales-' + sys.argv[3]),
                        ('User', 'hadoop'), ('State', 'FINISHED'), ('Final-State', 'SUCCEEDED')]:
    if not re.search(r'^\s*' + re.escape(label) + r'\s*:\s*' + re.escape(expected) + r'\s*$', text, re.M):
        raise SystemExit('YARN does not confirm own successful application: ' + label)
PY
nn_hdfs dfs -ls -R "$RUN_HDFS/daily_sales" > "$EVIDENCE_DIR/hdfs-output.txt"
nn_hdfs fsck "$RUN_HDFS/daily_sales" -files -blocks -locations > "$EVIDENCE_DIR/hdfs-fsck.txt"
grep -Eq '^Status:[[:space:]]+HEALTHY' "$EVIDENCE_DIR/hdfs-fsck.txt" || fail 'HDFS output is not HEALTHY'
nn_beeline -e "SET hive.fetch.task.conversion=more; SELECT dt,city,order_count,total_quantity,revenue FROM $HW5_DATABASE.$TABLE_NAME;" \
  > "$EVIDENCE_DIR/hive-rows.tsv" 2> "$EVIDENCE_DIR/hive-query.log"
nn_beeline -e "SHOW PARTITIONS $HW5_DATABASE.$TABLE_NAME;" \
  > "$EVIDENCE_DIR/hive-partitions.tsv" 2> "$EVIDENCE_DIR/hive-partitions.log"
python3 "$HW5_DIR/scripts/validate_fixture.py" \
  --hive-rows "$EVIDENCE_DIR/hive-rows.tsv" \
  --hive-partitions "$EVIDENCE_DIR/hive-partitions.tsv" \
  | tee "$EVIDENCE_DIR/verification.txt"
python3 - "$EVIDENCE_DIR" "$RUN_ID" "$app_id" "$HW5_DIR/data/expected.json" <<'PY'
import json
from pathlib import Path
import sys

evidence = Path(sys.argv[1])
expected = json.loads(Path(sys.argv[4]).read_text())
report = {'status': 'PASS', 'run_id': sys.argv[2], 'application_id': sys.argv[3],
          'table': 'dp_mashustova_hw5.daily_sales_' + sys.argv[2],
          'yarn_final_state': 'SUCCEEDED', 'spark_stopped': True, 'hdfs_fsck': 'HEALTHY',
          'beeline_exact_match': True, 'daily_sales': expected['daily_sales']}
(evidence / 'verification.json').write_text(json.dumps(report, indent=2) + '\n')
PY
printf '%s\n' "$RUN_ID" > "$EVIDENCE_DIR/verified.ok"
printf 'Verified YARN + Parquet + Hive: %s.%s (%s)\n' "$HW5_DATABASE" "$TABLE_NAME" "$app_id"
