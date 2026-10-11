#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
require_edge
require_installation
for node in "${NODES[@]}"; do
  on_node "$node" sudo -n -u "$HADOOP_USER" env "JAVA_HOME=$JAVA_HOME" "$HADOOP_HOME/bin/hdfs" --daemon stop datanode
done
hdfs_cmd --daemon stop secondarynamenode
hdfs_cmd --daemon stop namenode
for node in "${NODES[@]}"; do assert_stopped "$node"; done
