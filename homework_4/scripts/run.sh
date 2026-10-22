#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
set_run "${1:-r$(date -u +%Y%m%d_%H%M%S)}"
[[ ! -e "$EVIDENCE_DIR" ]] || fail 'Evidence exists; use a new run ID'
edge_hadoop test -x "$SPARK_HOME/bin/spark-submit"
edge_hadoop test ! -e "$JOB_DIR" || fail 'Job directory exists; use a new run ID'
client_classpath=$(edge_hadoop python3 "$HW4_RUNTIME_DIR/verify_runtime.py" "$SPARK_HOME" "$HW4_RUNTIME_DIR")
safe_mode=$(nn_hdfs dfsadmin -safemode get)
[[ "$safe_mode" == *'Safe mode is OFF'* ]] || fail "HDFS is not writable: $safe_mode"
nn_hdfs dfs -ls / >/dev/null
nn_yarn node -list
if nn_hdfs dfs -test -e "$RUN_HDFS"; then
  fail 'HDFS run directory exists; use a new run ID'
else
  code=$?
  [[ $code == 1 ]] || fail 'Cannot inspect HDFS run directory'
fi
mkdir -p "$EVIDENCE_DIR"
sudo -n install -d -o "$HADOOP_USER" -g "$(id -gn "$HADOOP_USER")" -m 750 "$JOB_DIR"
for name in daily_sales.py expected.json spark-defaults.conf; do
  case "$name" in
    daily_sales.py) source_file="$HW4_DIR/app/$name" ;;
    expected.json) source_file="$HW4_DIR/data/$name" ;;
    spark-defaults.conf) source_file="$HW4_DIR/configs/$name" ;;
  esac
  edge_hadoop tee "$JOB_DIR/$name" < "$source_file" >/dev/null
done
nn_hdfs dfs -mkdir -p "$RUN_HDFS/input" "$RUN_HDFS/events"
nn_hdfs dfs -put - "$RUN_HDFS/input/orders.csv" < "$HW4_DIR/data/orders.csv"
printf 'run_id=%s\ntable=%s.%s\noutput=%s\nmetastore=%s\n' "$RUN_ID" "$HW4_DATABASE" "$TABLE_NAME" "$OUTPUT_URI" "$HMS_URI" > "$EVIDENCE_DIR/run.txt"
sha256sum "$HW4_DIR/data/orders.csv" "$HW4_DIR/data/expected.json" "$HW4_DIR/app/daily_sales.py" > "$EVIDENCE_DIR/inputs.sha256"
edge_hadoop cat "$HW4_RUNTIME_DIR/runtime-manifest.json" > "$EVIDENCE_DIR/runtime-manifest.json"
submit_code=0
edge_hadoop env "PYSPARK_PYTHON=/usr/bin/python3" \
  timeout --signal=TERM --kill-after=30s 600s \
  "$SPARK_HOME/bin/spark-submit" --master yarn --deploy-mode client \
  --properties-file "$JOB_DIR/spark-defaults.conf" \
  --conf "spark.sql.hive.metastore.jars.path=$client_classpath" \
  --conf "spark.hadoop.hive.metastore.uris=$HMS_URI" \
  --conf "spark.driver.host=10.17.0.10" --conf "spark.driver.bindAddress=10.17.0.10" \
  --conf "spark.yarn.appMasterEnv.JAVA_HOME=$JAVA_HOME" --conf "spark.executorEnv.JAVA_HOME=$JAVA_HOME" \
  --conf "spark.eventLog.enabled=true" --conf "spark.eventLog.dir=$HDFS_URI$RUN_HDFS/events" \
  "$JOB_DIR/daily_sales.py" --table "$HW4_DATABASE.$TABLE_NAME" \
  --input "$HDFS_URI$RUN_HDFS/input/orders.csv" --output "$OUTPUT_URI" \
  --expected "$JOB_DIR/expected.json" --report "$JOB_DIR/spark-report.json" \
  2>&1 | tee "$EVIDENCE_DIR/spark-submit.log" || submit_code=$?
if edge_hadoop test -f "$JOB_DIR/spark-report.json"; then
  edge_hadoop cat "$JOB_DIR/spark-report.json" > "$EVIDENCE_DIR/spark-report.json"
fi
if [[ $submit_code != 0 ]]; then
  own_app_id=$(python3 "$HW4_DIR/scripts/resolve_application_id.py" "$EVIDENCE_DIR/spark-report.json" "$EVIDENCE_DIR/spark-submit.log")
  if [[ -n "$own_app_id" ]]; then
    cleanup_confirmed=false
    if nn_yarn application -kill "$own_app_id" > "$EVIDENCE_DIR/yarn-error-cleanup.txt" 2>&1; then
      for attempt in {1..15}; do
        if ! nn_yarn application -status "$own_app_id" > "$EVIDENCE_DIR/yarn-error-status.txt" 2>&1; then
          break
        fi
        if grep -Eq 'State[[:space:]]*:[[:space:]]*(FINISHED|FAILED|KILLED)' "$EVIDENCE_DIR/yarn-error-status.txt"; then
          cleanup_confirmed=true
          break
        fi
        sleep 2
      done
    fi
    if [[ "$cleanup_confirmed" != true ]]; then
      printf 'Own application cleanup is unconfirmed. On %s run:\n' "$NN_HOST" >&2
      printf 'sudo -n -H -u %s env JAVA_HOME=%s HADOOP_HOME=%s %s/bin/yarn application -status %s\n' "$HADOOP_USER" "$NN_CLI_JAVA_HOME" "$NN_HADOOP_HOME" "$NN_HADOOP_HOME" "$own_app_id" >&2
      printf 'If still active, run the same command with -kill instead of -status. See yarn-error-cleanup.txt and yarn-error-status.txt.\n' >&2
    fi
  fi
fi
if [[ $submit_code == 124 ]]; then
  fail "Spark exceeded 600 seconds; inspect YARN resources/application before retrying. Evidence: $EVIDENCE_DIR"
fi
if [[ $submit_code == 137 ]]; then
  fail "Spark received SIGKILL (timeout escalation or external kill); inspect YARN/system logs. Evidence: $EVIDENCE_DIR"
fi
[[ $submit_code == 0 ]] || fail "Spark failed (exit $submit_code); evidence: $EVIDENCE_DIR"
bash "$HW4_DIR/scripts/check.sh" "$RUN_ID"
