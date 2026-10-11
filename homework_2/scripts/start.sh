#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
require_installation
on_node "$RM_HOST" sudo -n -u "$HADOOP_USER" env "JAVA_HOME=$JAVA_HOME" "$HADOOP_HOME/bin/yarn" --daemon start resourcemanager
for node in "${NODES[@]}"; do
  on_node "$node" sudo -n -u "$HADOOP_USER" env "JAVA_HOME=$JAVA_HOME" "$HADOOP_HOME/bin/yarn" --daemon start nodemanager
done
on_node "$JHS_HOST" sudo -n -u "$HADOOP_USER" env "JAVA_HOME=$JAVA_HOME" "$HADOOP_HOME/bin/mapred" --daemon start historyserver
