#!/usr/bin/env bash
set -euo pipefail
HW3_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
NN_HOST=team-17-nn
NN_IP=10.17.0.11
SSH_USER=team
HADOOP_USER=hadoop
PLATFORM_ROOT=/home/hadoop/mashustova/platform
HADOOP_CLIENT_HOME=/opt/hadoop-3.4.0
HIVE_HOME=/opt/hive
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
HIVE_HOST=10.17.0.11
METASTORE_URI=thrift://team-17-nn:9083
METASTORE_DB=hive_metastore
METASTORE_USER=hive
WAREHOUSE=hdfs://team-17-nn:9000/user/hive/warehouse
HW3_DATABASE=dp_mashustova_hw3
HW3_HDFS_ROOT=hdfs://team-17-nn:9000/user/hadoop/mashustova/hw3
HW3_STAGE_DIR=/home/hadoop/mashustova/hw3
EXPECTED_HDFS_CLUSTER_ID=CID-4fb0782a-da44-497b-b906-8f8c7fdd4365
[[ ! -f "$HW3_DIR/local.env" ]] || source "$HW3_DIR/local.env"
HIVE_JAVA_HOME=$JAVA_HOME
HADOOP_HOME=$HADOOP_CLIENT_HOME
HDFS_URI=hdfs://team-17-nn:9000
HIVE_JDBC_URL=jdbc:hive2://$HIVE_HOST:10000/default
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
for path in "$PLATFORM_ROOT" "$HADOOP_CLIENT_HOME" "$HIVE_HOME" "$JAVA_HOME" "$HW3_STAGE_DIR"; do
  [[ $path =~ ^/[a-zA-Z0-9/._-]+$ && $path != *..* ]] || fail 'Use absolute installation paths without parent traversal'
done
[[ $HW3_DATABASE == dp_mashustova_hw3 && $HW3_HDFS_ROOT == "$HDFS_URI/user/hadoop/mashustova/hw3" ]] || fail 'Use only the personal homework_3 database and HDFS namespace'
[[ $HW3_STAGE_DIR == /home/hadoop/mashustova/hw3 ]] || fail 'Use the personal homework_3 staging directory'
for identifier in "$METASTORE_DB" "$METASTORE_USER"; do
  [[ $identifier =~ ^[a-z][a-z0-9_]{0,50}$ ]] || fail 'Invalid PostgreSQL identifier'
done
export NN_HOST NN_IP HADOOP_USER HADOOP_HOME JAVA_HOME HIVE_JAVA_HOME PLATFORM_ROOT HADOOP_CLIENT_HOME HIVE_HOME HIVE_HOST WAREHOUSE HW3_HDFS_ROOT HW3_DATABASE
run_hadoop() {
  sudo -n -H -u "$HADOOP_USER" env "JAVA_HOME=$JAVA_HOME" "HADOOP_HOME=$HADOOP_CLIENT_HOME" "HADOOP_CONF_DIR=$HADOOP_CLIENT_HOME/etc/hadoop" "HIVE_HOME=$HIVE_HOME" "HIVE_CONF_DIR=$HIVE_HOME/conf" "HADOOP_HEAPSIZE=256" "HADOOP_CLIENT_OPTS=-Xmx256m" "$@"
}
edge_hadoop() { run_hadoop "$@"; }
hive_hadoop() { run_hadoop "$@"; }
client_hdfs() { run_hadoop "$HADOOP_CLIENT_HOME/bin/hdfs" "$@"; }
beeline_cmd() {
  hive_hadoop timeout 180 "$HIVE_HOME/bin/beeline" -u "$HIVE_JDBC_URL" -n "$HADOOP_USER" --silent=true --showHeader=false --outputformat=tsv2 --color=false --force=false "$@"
}
run_sql() { local file=$1; shift; beeline_cmd "$@" -f /dev/stdin < "$file"; }
require_node() {
  [[ $(id -un) == "$SSH_USER" ]] || fail "Run as $SSH_USER on $NN_HOST"
  [[ $(hostname -s) == "$NN_HOST" ]] || fail "Run on $NN_HOST (NameNode)"
  sudo -n true
}
require_hive_installation() {
  require_node
  run_hadoop test -x "$HADOOP_CLIENT_HOME/bin/hdfs"
  run_hadoop test -x "$HIVE_HOME/bin/hive"
  run_hadoop test -x "$JAVA_HOME/bin/java"
  run_hadoop test -r "$HIVE_HOME/conf/hive-site.xml"
}
require_hdfs_cluster() {
  [[ $EXPECTED_HDFS_CLUSTER_ID =~ ^CID-[a-zA-Z0-9-]+$ ]] || fail 'Set EXPECTED_HDFS_CLUSTER_ID to the independently verified current clusterID in local.env'
  local filesystem name_dirs
  filesystem=$(client_hdfs getconf -confKey fs.defaultFS)
  name_dirs=$(client_hdfs getconf -confKey dfs.namenode.name.dir)
  run_hadoop python3 - "$EXPECTED_HDFS_CLUSTER_ID" "$HDFS_URI" "$filesystem" "$name_dirs" < "$HW3_DIR/scripts/validate_cluster.py"
  client_hdfs dfsadmin -safemode get | grep -q 'Safe mode is OFF'
}
