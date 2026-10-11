#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
require_edge
require_installation
run_id=$(date -u +%Y%m%dT%H%M%SZ)-$$
evidence=$HW1_ROOT/evidence/runtime-$run_id
mkdir -p "$evidence"
bounded_hdfs() { on_node "$NN_HOST" sudo -n -u "$HADOOP_USER" env "JAVA_HOME=$JAVA_HOME" timeout 120 "$HADOOP_HOME/bin/hdfs" "$@"; }
ready=false
for attempt in {1..30}; do
  bounded_hdfs dfsadmin -report > "$evidence/dfsadmin-report.txt"
  bounded_hdfs dfsadmin -safemode get > "$evidence/safemode.txt"
  if grep -q 'Live datanodes (3)' "$evidence/dfsadmin-report.txt" && ! grep -Eq 'Dead datanodes \([1-9][0-9]*\)' "$evidence/dfsadmin-report.txt" && grep -q 'Safe mode is OFF' "$evidence/safemode.txt"; then
    ready=true
    break
  fi
  sleep 2
done
[[ $ready == true ]] || fail "Cluster not healthy: see $evidence"
for node in "${NODES[@]}"; do
  on_node "$node" sudo -n -u "$HADOOP_USER" "$JAVA_HOME/bin/jps" -l > "$evidence/$node-jps.txt"
  grep -q 'org.apache.hadoop.hdfs.server.datanode.DataNode' "$evidence/$node-jps.txt"
  if [[ $node == "$NN_HOST" ]]; then
    grep -q 'org.apache.hadoop.hdfs.server.namenode.NameNode' "$evidence/$node-jps.txt"
    grep -q 'org.apache.hadoop.hdfs.server.namenode.SecondaryNameNode' "$evidence/$node-jps.txt"
  fi
  on_node "$node" bash -se -- "$HADOOP_HOME" "$HADOOP_USER" <<'REMOTE' > "$evidence/$node-log-tail.txt"
set -euo pipefail
sudo -n -u "$2" bash -c 'shopt -s nullglob; logs=("$1"/logs/*.log); [[ ${#logs[@]} -gt 0 ]]; tail -n 100 "${logs[@]}"' _ "$1"
REMOTE
done
path=/user/$HADOOP_USER/hw1/$run_id/hello.txt
expected='Hello from team-17: three replicas and a verified read.'
bounded_hdfs dfs -mkdir -p "${path%/*}"
printf '%s\n' "$expected" | bounded_hdfs dfs -put - "$path"
bounded_hdfs dfs -cat "$path" > "$evidence/read-back.txt"
[[ $(cat "$evidence/read-back.txt") == "$expected" ]] || fail 'HDFS read differs from input'
bounded_hdfs dfs -setrep -w 3 "$path" > "$evidence/setrep.txt"
bounded_hdfs fsck "$path" -files -blocks -locations > "$evidence/fsck.txt"
grep -q 'Status: HEALTHY' "$evidence/fsck.txt"
grep -q 'Live_repl=3' "$evidence/fsck.txt"
printf 'UTC run: %s\nHDFS file: %s\nCLI checks: PASS\n' "$run_id" "$path" > "$evidence/result.txt"
