#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
require_installation
mkdir -p "$HW2_DIR/evidence"
run=$(date -u +%Y%m%dT%H%M%SZ)
report="$HW2_DIR/evidence/yarn-$run.txt"
{
  date -u
  nodes=$(yarn_cmd node -list -all)
  printf '%s\n' "$nodes"
  [[ $(printf '%s\n' "$nodes" | awk '$2 == "RUNNING" {n++} END {print n+0}') == 3 ]]
  on_node "$JHS_HOST" curl --fail --silent --show-error "http://$JHS_HOST:19888/ws/v1/history/info"
  printf '\n'
  for node in "${NODES[@]}"; do
    on_node "$node" curl --fail --silent --show-error "http://localhost:8042/ws/v1/node/info"
    printf '\n'
  done
  if output=$(on_node "$NN_HOST" sudo -n -u "$HADOOP_USER" env "JAVA_HOME=$JAVA_HOME" timeout 300 "$HADOOP_HOME/bin/hadoop" jar "$HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.4.0.jar" pi 3 1000 2>&1); then
    :
  else
    result=$?
    printf '%s\n' "$output"
    echo "MapReduce failed or timed out (exit $result); inspect yarn application -list -appStates ALL and yarn logs -applicationId ID" >&2
    exit "$result"
  fi
  printf '%s\n' "$output"
  app=$(printf '%s\n' "$output" | sed -nE 's/.*(application_[0-9]+_[0-9]+).*/\1/p' | tail -n 1)
  [[ -n "$app" ]]
  status=$(yarn_cmd application -status "$app" 2>&1)
  printf '%s\n' "$status"
  printf '%s\n' "$status" | grep -Eq 'State[[:space:]]*:[[:space:]]*FINISHED'
  printf '%s\n' "$status" | grep -Eq 'Final-State[[:space:]]*:[[:space:]]*SUCCEEDED'
  printf '%s\n' "$output" | grep -q 'Estimated value of Pi is'
  job=${app/application_/job_}
  history=$(curl --fail --silent --show-error --retry 10 --retry-delay 2 --retry-all-errors "http://$JHS_HOST:19888/ws/v1/history/mapreduce/jobs/$job")
  printf '%s\n' "$history"
  printf '%s\n' "$history" | python3 -c 'import json,sys; job=json.load(sys.stdin)["job"]; assert job["state"] == "SUCCEEDED"; assert job["mapsCompleted"] == 3 and job["reducesCompleted"] == 1'

} 2>&1 | tee "$report"
