#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
require_edge
require_installation
on_node "$NN_HOST" sudo -n -u "$HADOOP_USER" test -s "$HADOOP_USER_HOME/hdfs/name/current/VERSION"
hdfs_cmd --daemon start namenode
hdfs_cmd --daemon start secondarynamenode
for node in "${NODES[@]}"; do
  on_node "$node" sudo -n -u "$HADOOP_USER" env "JAVA_HOME=$JAVA_HOME" "$HADOOP_HOME/bin/hdfs" --daemon start datanode
done
