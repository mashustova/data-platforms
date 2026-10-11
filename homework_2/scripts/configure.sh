#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
require_installation
work=$(mktemp -d -t hw2.XXXXXX)
trap 'rm -rf "$work"' EXIT
for index in "${!NODES[@]}"; do
  node=${NODES[$index]}
  mb=${NM_MEMORY_MB[$index]}
  python3 "$HW2_DIR/scripts/render.py" --output "$work/$node" --rm "$RM_HOST" --jhs "$JHS_HOST" --hadoop-home "$HADOOP_HOME" --java-home "$JAVA_HOME" --memory "$mb" --vcores "$CONTAINER_VCORES"
  for host in "$NN_HOST" "$RM_HOST" "$JHS_HOST"; do
    on_node "$node" python3 -c 'import ipaddress,socket,sys; addresses={r[4][0] for r in socket.getaddrinfo(sys.argv[1],None,socket.AF_INET)}; assert all(not ipaddress.ip_address(ip).is_loopback for ip in addresses), (sys.argv[1],addresses)' "$host"
  done
  for binary in yarn mapred hadoop; do
    on_node "$node" sudo -n -u "$HADOOP_USER" test -x "$HADOOP_HOME/bin/$binary"
  done
  on_node "$node" sudo -n -u "$HADOOP_USER" test -r "$HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.4.0.jar"
  on_node "$node" bash -se -- "$HADOOP_USER" <<'REMOTE'
if sudo -n pgrep -u "$1" -f 'org.apache.hadoop.(yarn|mapred)' >/dev/null; then
  echo 'Stop YARN and JobHistory before replacing configs' >&2
  exit 1
else
  result=$?
  [[ $result == 1 ]] || exit "$result"
fi
REMOTE
  reserve=$((1024 + 512 + 256))
  [[ "$node" != "$NN_HOST" ]] || reserve=$((reserve + 1024))
  [[ "$node" != "$RM_HOST" ]] || reserve=$((reserve + 512))
  [[ "$node" != "$JHS_HOST" ]] || reserve=$((reserve + 256))
  on_node "$node" bash -se -- "$((mb + reserve))" <<'REMOTE'
required=$1
available=$(awk '/MemTotal:/ {print int($2 / 1024)}' /proc/meminfo)
(( available >= required )) || { echo "Need $required MB total, found $available; adjust budgets before continuing" >&2; exit 1; }
REMOTE
done
for node in "${NODES[@]}"; do
  group=$(on_node "$node" id -gn "$HADOOP_USER")
  on_node "$node" sudo -n install -d -o "$HADOOP_USER" -g "$group" /data/hadoop/yarn/local /data/hadoop/yarn/logs /data/hadoop/logs /data/hadoop/pids
  for file in yarn-site.xml mapred-site.xml yarn-env.sh mapred-env.sh; do
    on_node "$node" bash -se -- "$HADOOP_HOME/etc/hadoop/$file" <<'REMOTE'
file=$1
if [[ -e "$file" ]]; then sudo -n cp -p "$file" "$file.before-hw2.$(date +%s)"; fi
REMOTE
    on_node "$node" sudo -n -u "$HADOOP_USER" tee "$HADOOP_HOME/etc/hadoop/$file" < "$work/$node/$file" >/dev/null
  done
done
hdfs_cmd dfs -mkdir -p /user/"$HADOOP_USER" /mr-history/tmp /mr-history/done /yarn-logs
hdfs_cmd dfs -chmod 1777 /mr-history/tmp /yarn-logs
hdfs_cmd dfs -chmod 750 /mr-history/done
