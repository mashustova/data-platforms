#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
set_run "${1:?Usage: spark_etl.sh RUN_ID}"
require_marker staged
[[ ! -e "$EVIDENCE_DIR/submission.started" ]] || fail 'Submission already attempted; inspect this run instead of resubmitting it'
client_classpath=$(read_classpath)
sha256sum -c "$EVIDENCE_DIR/inputs.sha256" > "$EVIDENCE_DIR/input-recheck.txt"
printf '%s\n' "$RUN_ID" > "$EVIDENCE_DIR/submission.started"
cleanup_after_failure() {
  local exit_code=$1
  trap '' TERM INT
  collect_spark_report || true
  if ! timeout --signal=TERM --kill-after=5s 90s bash "$HW5_DIR/scripts/cleanup.sh" "$RUN_ID"; then
    printf 'Cleanup not confirmed. Inspect %s and run cleanup.sh %s before another flow.\n' "$EVIDENCE_DIR" "$RUN_ID" >&2
  fi
  exit "$exit_code"
}
trap 'cleanup_after_failure 143' TERM
trap 'cleanup_after_failure 130' INT
submit_code=0
edge_hadoop env "PYSPARK_PYTHON=/usr/bin/python3" \
  timeout --signal=TERM --kill-after=30s 600s \
  "$SPARK_HOME/bin/spark-submit" --master yarn --deploy-mode client \
  --name "team17-hw5-daily-sales-$RUN_ID" \
  --properties-file "$JOB_DIR/spark-defaults.conf" \
  --conf "spark.sql.hive.metastore.jars.path=$client_classpath" \
  --conf "spark.hadoop.hive.metastore.uris=$HMS_URI" \
  --conf 'spark.driver.host=10.17.0.10' --conf 'spark.driver.bindAddress=10.17.0.10' \
  --conf "spark.yarn.appMasterEnv.JAVA_HOME=$JAVA_HOME" --conf "spark.executorEnv.JAVA_HOME=$JAVA_HOME" \
  --conf 'spark.eventLog.enabled=true' --conf "spark.eventLog.dir=$HDFS_URI$RUN_HDFS/events" \
  "$JOB_DIR/daily_sales.py" --table "$HW5_DATABASE.$TABLE_NAME" \
  --input "$HDFS_URI$RUN_HDFS/input/orders.csv" --output "$OUTPUT_URI" \
  --expected "$JOB_DIR/expected.json" --report "$JOB_DIR/spark-report.json" \
  2>&1 | tee "$EVIDENCE_DIR/spark-submit.log" || submit_code=$?
collect_spark_report || { cleanup_after_failure 1; }
if [[ $submit_code != 0 ]]; then
  printf 'Spark failed (exit %s). Evidence: %s\n' "$submit_code" "$EVIDENCE_DIR" >&2
  cleanup_after_failure "$submit_code"
fi
[[ -f "$EVIDENCE_DIR/spark-report.json" ]] || { cleanup_after_failure 1; }
printf '%s\n' "$RUN_ID" > "$EVIDENCE_DIR/spark.ok"
trap - TERM INT
