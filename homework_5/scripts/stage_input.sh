#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
set_run "${1:?Usage: stage_input.sh RUN_ID}"
require_marker preflight
mkdir "$EVIDENCE_DIR/stage.started" || fail 'Staging was already attempted; inspect evidence and use a new run ID'
edge_hadoop test ! -e "$JOB_DIR" || fail 'Job directory exists; use a new run ID'
if nn_hdfs dfs -test -e "$RUN_HDFS"; then
  fail 'HDFS run directory exists; use a new run ID'
else
  code=$?
  [[ $code == 1 ]] || fail 'Cannot inspect HDFS run directory'
fi
sudo -n install -d -o "$HADOOP_USER" -g "$(id -gn "$HADOOP_USER")" -m 750 "$HW5_WORK_ROOT/jobs"
edge_hadoop mkdir -m 750 "$JOB_DIR"
for name in daily_sales.py expected.json spark-defaults.conf; do
  case "$name" in
    daily_sales.py) source_file="$HW5_DIR/app/$name" ;;
    expected.json) source_file="$HW5_DIR/data/$name" ;;
    spark-defaults.conf) source_file="$HW5_DIR/configs/$name" ;;
  esac
  edge_hadoop tee "$JOB_DIR/$name" < "$source_file" >/dev/null
done
nn_hdfs dfs -mkdir -p "$HW5_HDFS_ROOT/runs"
nn_hdfs dfs -mkdir "$RUN_HDFS"
nn_hdfs dfs -mkdir "$RUN_HDFS/input" "$RUN_HDFS/events"
nn_hdfs dfs -put - "$RUN_HDFS/input/orders.csv" < "$HW5_DIR/data/orders.csv"
printf 'run_id=%s\ntable=%s.%s\noutput=%s\nmetastore=%s\n' "$RUN_ID" "$HW5_DATABASE" "$TABLE_NAME" "$OUTPUT_URI" "$HMS_URI" > "$EVIDENCE_DIR/run.txt"
sha256sum "$HW5_DIR/data/orders.csv" "$HW5_DIR/data/expected.json" "$HW5_DIR/app/daily_sales.py" "$HW5_DIR/configs/spark-defaults.conf" > "$EVIDENCE_DIR/inputs.sha256"
printf '%s\n' "$RUN_ID" > "$EVIDENCE_DIR/staged.ok"
